function Get-CIPPAddonLayout {
    <#
    .SYNOPSIS
        Where each part of a Community Additions add-on lives, in a package and in the repository
        (Config/AddonLayout.json).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CIPPAddonLayout) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
        $script:CIPPAddonLayout = Get-Content -Path (Join-Path $Root 'Config/AddonLayout.json') -Raw | ConvertFrom-Json
    }
    $script:CIPPAddonLayout
}
