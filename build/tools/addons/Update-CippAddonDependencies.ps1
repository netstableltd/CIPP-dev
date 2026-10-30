<#
.SYNOPSIS
    Rewrites dependsOn in an add-on's addon.json from its code.

.DESCRIPTION
    dependsOn lists what the add-on uses from CIPP itself: the CIPP functions its backend code calls and
    the frontend files it imports from outside its own folders. The add-on manager checks the functions
    are there at runtime, Test-CippAddonUpstream.ps1 checks both against a new upstream CIPP, and the
    add-on tests fail when the list is out of date, so run this after changing an add-on's code.

.EXAMPLE
    pwsh build/tools/addons/Update-CippAddonDependencies.ps1 -All
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(ParameterSetName = 'One', Mandatory)][string]$Id,
    [Parameter(ParameterSetName = 'All', Mandatory)][switch]$All
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonTools.ps1')
$Layout = Get-AddonToolLayout
$CoreIndex = Get-AddonCoreFunctionIndex
$Ids = if ($All) { @(Get-ChildItem (Join-Path $RepoRoot 'backend/Config/Addons') -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'addon.json') } | ForEach-Object { $_.Name }) } else { @($Id) }
foreach ($AddonId in $Ids) {
    $Path = Get-AddonRepoPath -Template $Layout.manifest.repo -Id $AddonId
    $Json = Get-Content $Path -Raw
    $Manifest = $Json | ConvertFrom-Json -AsHashtable
    $Deps = Get-AddonDependencies -Id $AddonId -Layout $Layout -CoreIndex $CoreIndex
    $Before = ($Manifest.dependsOn | ConvertTo-Json -Depth 5 -Compress)
    if (-not $Manifest.dependsOn) { $Manifest.dependsOn = [ordered]@{} }
    $Manifest.dependsOn.functions = @($Deps.functions)
    $Manifest.dependsOn.frontend = @($Deps.frontend)
    $After = ($Manifest.dependsOn | ConvertTo-Json -Depth 5 -Compress)
    if ($Before -eq $After) { Write-Host "$($AddonId): up to date."; continue }
    if ($PSCmdlet.ShouldProcess($Path, 'Update dependsOn')) {
        # Keep the manifest's key order: ConvertFrom-Json -AsHashtable returns an ordered dictionary.
        ($Manifest | ConvertTo-Json -Depth 10) + "`n" | Set-Content -Path $Path -NoNewline
        Write-Host "$($AddonId): dependsOn updated ($($Deps.functions.Count) functions, $($Deps.frontend.Count) frontend files)."
    }
}
