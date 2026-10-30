<#
.SYNOPSIS
    Removes a Community Additions add-on's files from this repository.

.DESCRIPTION
    Deletes the add-on's folders (backend/Config/AddonLayout.json lists them). It doesn't commit
    anything: review, then commit and push so the image is rebuilt without it.

    What stays: data the add-on stored (its tables are listed under storage in addon.json) and its
    feature-flag row. Export a package first if you might want it back.

.EXAMPLE
    pwsh build/tools/addons/Uninstall-CippAddon.ps1 -Id claude-m365
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param([Parameter(Mandatory)][string]$Id)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonTools.ps1')

if ($Id -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') { throw "'$Id' isn't an add-on id." }
$Layout = Get-AddonToolLayout
$ManifestPath = Get-AddonRepoPath -Template $Layout.manifest.repo -Id $Id
if (-not (Test-Path $ManifestPath)) { throw "There's no add-on '$Id'." }
$Manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json

if ($PSCmdlet.ShouldProcess($Id, "Remove $($Manifest.name) $($Manifest.version)")) {
    $Removed = foreach ($Area in $Layout.areas) {
        $Folder = Get-AddonRepoPath -Template $Area.repo -Id $Id
        if (Test-Path $Folder) { Remove-Item -Path $Folder -Recurse -Force; [System.IO.Path]::GetRelativePath($RepoRoot, $Folder) }
    }
    if (Test-Path $ManifestPath) { Remove-Item $ManifestPath -Force }
    Write-Host "Removed $Id $($Manifest.version)." -ForegroundColor Green
    foreach ($S in @($Manifest.storage)) { if ($S.table) { Write-Host "Left in place: table $($S.table) ($($S.what))" } }
    [pscustomobject]@{ Id = $Id; Version = $Manifest.version; Removed = @($Removed) }
}
