function Get-CIPPRunningVersion {
    <#
    .SYNOPSIS
        The CIPP version this instance runs, as x.y.z.

    .DESCRIPTION
        version_latest.txt (upstream's own version file) when it is there, otherwise the image's
        APP_VERSION (for example 11.2.1+preview.reports.abc1234), without the build suffix.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
    $Version = try { (Get-Content -Path (Join-Path $Root 'version_latest.txt') -Raw -ErrorAction Stop).Trim() } catch { $null }
    if (-not $Version -and $env:APP_VERSION) { $Version = $env:APP_VERSION }
    if ($Version -match '^\s*v?(\d+\.\d+\.\d+)') { return $Matches[1] }
    $null
}
