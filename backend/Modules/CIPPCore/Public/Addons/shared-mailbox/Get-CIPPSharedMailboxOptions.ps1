function Get-CIPPSharedMailboxOptions {
    <#
    .SYNOPSIS
        The shared mailbox add-on's questions for the customer, each option with what it means and our
        recommendation (Config/Addons/shared-mailbox/SharedMailboxOptions.json).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CIPPSharedMailboxOptions) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../../..' }
        $script:CIPPSharedMailboxOptions = Get-Content -Path (Join-Path $Root 'Config/Addons/shared-mailbox/SharedMailboxOptions.json') -Raw | ConvertFrom-Json
    }
    $script:CIPPSharedMailboxOptions
}
