function Get-CIPPAddonManifest {
    <#
    .SYNOPSIS
        The manifests (addon.json) of the Community Additions add-ons installed in this CIPP.

    .DESCRIPTION
        Each add-on keeps its manifest at Config/Addons/<id>/addon.json. A manifest that can't be read, or
        whose id doesn't match its folder, is returned with an Error so the manager can show it rather
        than silently dropping it.

    .PARAMETER Id
        Only this add-on.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Id)

    $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
    $Folder = Join-Path $Root 'Config/Addons'
    if (-not (Test-Path -Path $Folder)) { return }
    foreach ($Dir in Get-ChildItem -Path $Folder -Directory | Sort-Object Name) {
        if ($Id -and $Dir.Name -ne $Id) { continue }
        $Path = Join-Path $Dir.FullName 'addon.json'
        if (-not (Test-Path -Path $Path)) { continue }
        try {
            $Manifest = Get-Content -Path $Path -Raw | ConvertFrom-Json -ErrorAction Stop
            $Problems = @(Test-CIPPAddonManifest -Manifest $Manifest -Id $Dir.Name)
            $Manifest | Add-Member -NotePropertyName ManifestErrors -NotePropertyValue $Problems -Force
            $Manifest
        } catch {
            [pscustomobject]@{ id = $Dir.Name; name = $Dir.Name; version = $null; ManifestErrors = @("addon.json can't be read: $($_.Exception.Message)") }
        }
    }
}
