function Get-CIPPSharedMailboxSignatureRuleName {
    <#
    .SYNOPSIS
        The name of the mail flow rule that adds a shared mailbox's signature (transport rule names are at
        most 64 characters).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Address)

    $Name = "Shared mailbox signature - $($Address.ToLowerInvariant())"
    if ($Name.Length -gt 64) { $Name = $Name.Substring(0, 64) }
    $Name
}
