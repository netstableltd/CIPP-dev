function Get-CIPPAddonInstalledPackage {
    <#
    .SYNOPSIS
        The package (.zip) of an installed add-on, made when this CIPP image was built.

    .DESCRIPTION
        The image build packages every installed add-on into Config/AddonPackages/<id>.zip (with
        build/tools/addons/Export-CippAddon.ps1), because the add-on's source files aren't in the image
        on their own: the backend is compiled into modules and the frontend into static pages. Returns
        $null when there is no package (a local run that wasn't built as an image).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Id)

    if ($Id -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') { return $null }
    $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
    $Path = Join-Path $Root "Config/AddonPackages/$Id.zip"
    if (-not (Test-Path -Path $Path)) { return $null }
    $Bytes = [System.IO.File]::ReadAllBytes($Path)
    [pscustomobject]@{ Path = $Path; Bytes = $Bytes; Check = (Test-CIPPAddonPackage -Bytes $Bytes) }
}
