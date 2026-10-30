<#
.SYNOPSIS
    Installs a Community Additions add-on package (.zip) into this repository.

.DESCRIPTION
    Checks the package (the same checks as the add-on manager), then copies each folder in it to its
    place in the repository (backend/Config/AddonLayout.json). It doesn't commit anything: review the
    changes, run the tests, then commit and push so the image is rebuilt.

    Installing an add-on that is already installed is refused unless -Upgrade is given; an upgrade
    removes the add-on's current files first, so files dropped from the new version don't linger.

    A backend function or endpoint with the same name as one already in CIPP (outside this add-on) is
    refused: the module build would load one over the other.

.EXAMPLE
    pwsh build/tools/addons/Install-CippAddon.ps1 -Path ./claude-m365-1.3.0.zip
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)][string]$Path,
    [switch]$Upgrade
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonTools.ps1')
Add-Type -AssemblyName System.IO.Compression

$Layout = Get-AddonToolLayout
$Check = Test-CIPPAddonPackage -Path $Path -Layout $Layout
foreach ($W in $Check.Warnings) { Write-Warning $W }
if (-not $Check.Valid) { throw "The package didn't pass the checks:`n - $($Check.Errors -join "`n - ")" }
$Manifest = $Check.Manifest
$Id = $Manifest.id

$ManifestPath = Get-AddonRepoPath -Template $Layout.manifest.repo -Id $Id
if ((Test-Path $ManifestPath) -and -not $Upgrade) {
    $Current = Get-Content $ManifestPath -Raw | ConvertFrom-Json
    throw "$Id $($Current.version) is already installed. Use -Upgrade to replace it with $($Manifest.version)."
}

# Name clashes with CIPP's own functions (anything outside this add-on's folders).
$OwnFolders = @($Layout.areas | ForEach-Object { (Get-AddonRepoPath -Template $_.repo -Id $Id) })
$NewFunctions = @($Check.Files | Where-Object { $_.Area -in 'backend/functions', 'backend/endpoints' } | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Path) })
if ($NewFunctions.Count) {
    $Existing = Get-ChildItem -Path (Join-Path $RepoRoot 'backend/Modules') -Filter '*.ps1' -Recurse |
        Where-Object { $P = $_.FullName; -not ($OwnFolders | Where-Object { $P.StartsWith($_) }) -and $NewFunctions -contains $_.BaseName }
    if ($Existing) { throw "These would clash with functions already in CIPP: $(@($Existing | ForEach-Object { [System.IO.Path]::GetRelativePath($RepoRoot, $_.FullName) }) -join ', ')" }
}

$Running = Get-AddonRepoVersion
$Compat = Test-CIPPAddonCompatibility -Manifest $Manifest -CippVersion $Running -SkipRuntimeCheck
if ($Compat.Status -ne 'Compatible') { Write-Warning "$($Compat.Status): $($Compat.Message)" }

if ($PSCmdlet.ShouldProcess($Id, "Install $($Manifest.version)")) {
    if ($Upgrade) { & (Join-Path $PSScriptRoot 'Uninstall-CippAddon.ps1') -Id $Id -Confirm:$false | Out-Null }
    $Zip = [System.IO.Compression.ZipFile]::OpenRead((Resolve-Path $Path).Path)
    try {
        foreach ($Entry in $Zip.Entries) {
            if ($Entry.FullName.EndsWith('/') -or $Entry.FullName -eq 'checksums.json') { continue }
            $Target = if ($Entry.FullName -eq $Layout.manifest.package) { $ManifestPath } else {
                $Area = $Layout.areas | Where-Object { $Entry.FullName.StartsWith("$($_.package)/") } | Select-Object -First 1
                Join-Path (Get-AddonRepoPath -Template $Area.repo -Id $Id) $Entry.FullName.Substring($Area.package.Length + 1)
            }
            # Belt and braces on top of the package check: never write outside the repository.
            $Full = [System.IO.Path]::GetFullPath($Target)
            if (-not $Full.StartsWith($RepoRoot + [System.IO.Path]::DirectorySeparatorChar)) { throw "Refusing to write outside the repository: $($Entry.FullName)" }
            $null = New-Item -ItemType Directory -Path (Split-Path $Full) -Force
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($Entry, $Full, $true)
        }
    } finally { $Zip.Dispose() }

    Write-Host "Installed $Id $($Manifest.version) ($($Check.Files.Count + 1) files)." -ForegroundColor Green
    Write-Host 'Next: run the tests (Invoke-Pester backend/Tests/Addons; yarn test tests/addons),'
    Write-Host 'regenerate the API spec (build/tools/build-openapi.ps1), review with git status, then commit and push.'
    [pscustomobject]@{ Id = $Id; Version = $Manifest.version; Compatibility = $Compat.Status; Message = $Compat.Message }
}
