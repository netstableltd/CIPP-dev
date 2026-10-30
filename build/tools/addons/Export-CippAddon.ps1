<#
.SYNOPSIS
    Packages a Community Additions add-on from this repository into a .zip.

.DESCRIPTION
    Collects the add-on's files from the folders in backend/Config/AddonLayout.json, puts addon.json at
    the top and adds checksums.json (a SHA-256 for every file, and the CIPP version it was packaged on).
    The package is then checked with the same checks the add-on manager uses for uploads, and the
    export fails if it doesn't pass.

    Files are added in a fixed order with a fixed timestamp, so packaging the same files twice gives
    the same files inside.

.PARAMETER Id
    The add-on to package (its folder name under backend/Config/Addons). Use -All for every add-on.

.PARAMETER OutputPath
    Folder for the .zip files (default: ./addon-packages). Each is named <id>-<version>.zip, or
    <id>.zip with -NameById (what the image build uses).

.EXAMPLE
    pwsh build/tools/addons/Export-CippAddon.ps1 -Id claude-m365
#>
[CmdletBinding()]
param(
    [Parameter(ParameterSetName = 'One', Mandatory)][string]$Id,
    [Parameter(ParameterSetName = 'All', Mandatory)][switch]$All,
    [string]$OutputPath = (Join-Path (Get-Location) 'addon-packages'),
    [switch]$NameById
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonTools.ps1')
Add-Type -AssemblyName System.IO.Compression

$Layout = Get-AddonToolLayout
$Ids = if ($All) {
    @(Get-ChildItem -Path (Join-Path $RepoRoot 'backend/Config/Addons') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'addon.json') } | ForEach-Object { $_.Name })
} else { @($Id) }
$null = New-Item -ItemType Directory -Path $OutputPath -Force
$CippVersion = Get-AddonRepoVersion
$Sha = [System.Security.Cryptography.SHA256]::Create()
$Hex = { param([byte[]]$B) ([System.BitConverter]::ToString($Sha.ComputeHash($B)) -replace '-').ToLowerInvariant() }

foreach ($AddonId in $Ids) {
    $ManifestPath = Get-AddonRepoPath -Template $Layout.manifest.repo -Id $AddonId
    if (-not (Test-Path $ManifestPath)) { throw "There's no add-on '$AddonId' ($ManifestPath not found)." }
    $Manifest = Get-Content -Path $ManifestPath -Raw | ConvertFrom-Json

    # package path -> bytes
    $Content = [ordered]@{}
    $Content[$Layout.manifest.package] = [System.IO.File]::ReadAllBytes($ManifestPath)
    foreach ($Area in $Layout.areas) {
        $Folder = Get-AddonRepoPath -Template $Area.repo -Id $AddonId
        if (-not (Test-Path $Folder)) { continue }
        foreach ($File in Get-ChildItem -Path $Folder -File -Recurse | Sort-Object FullName) {
            if ($File.FullName -eq (Resolve-Path $ManifestPath).Path) { continue }
            if ($Area.extensions -notcontains $File.Extension.ToLowerInvariant()) {
                Write-Warning "Skipping $($File.FullName): $($Area.label) can only be $($Area.extensions -join ', ') files."
                continue
            }
            $Rel = [System.IO.Path]::GetRelativePath($Folder, $File.FullName) -replace '\\', '/'
            $Content["$($Area.package)/$Rel"] = [System.IO.File]::ReadAllBytes($File.FullName)
        }
    }
    $Checksums = [ordered]@{
        schema     = 1
        id         = $Manifest.id
        version    = $Manifest.version
        packagedOn = $CippVersion
        packagedAt = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        files      = [ordered]@{}
    }
    foreach ($Key in $Content.Keys) { $Checksums.files[$Key] = & $Hex $Content[$Key] }
    $Content['checksums.json'] = [System.Text.Encoding]::UTF8.GetBytes(($Checksums | ConvertTo-Json -Depth 5))

    $Target = Join-Path $OutputPath $(if ($NameById) { "$($Manifest.id).zip" } else { "$($Manifest.id)-$($Manifest.version).zip" })
    if (Test-Path $Target) { Remove-Item $Target -Force }
    $Stream = [System.IO.File]::Open($Target, [System.IO.FileMode]::CreateNew)
    try {
        $Zip = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Create)
        try {
            foreach ($Key in $Content.Keys) {
                $Entry = $Zip.CreateEntry($Key, [System.IO.Compression.CompressionLevel]::Optimal)
                $Entry.LastWriteTime = [datetimeoffset]::new(2020, 1, 1, 0, 0, 0, [timespan]::Zero)
                $W = $Entry.Open(); try { $W.Write($Content[$Key], 0, $Content[$Key].Length) } finally { $W.Dispose() }
            }
        } finally { $Zip.Dispose() }
    } finally { $Stream.Dispose() }

    $Check = Test-CIPPAddonPackage -Path $Target -Layout $Layout
    foreach ($W in $Check.Warnings) { Write-Warning "$($Manifest.id): $W" }
    if (-not $Check.Valid) {
        Remove-Item $Target -Force
        throw "$($Manifest.id) didn't pass the package checks:`n - $($Check.Errors -join "`n - ")"
    }
    [pscustomobject]@{ Id = $Manifest.id; Version = $Manifest.version; Files = $Check.Files.Count + 1; Bytes = $Check.Bytes; Sha256 = $Check.Sha256; Path = $Target }
}
