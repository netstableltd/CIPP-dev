function Get-CIPPSharedMailboxList {
    <#
    .SYNOPSIS
        The tenant's shared mailboxes (display name and address), for choosing one to set up.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$TenantFilter)

    @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ RecipientTypeDetails = 'SharedMailbox'; ResultSize = 'Unlimited' } -Select 'DisplayName,PrimarySmtpAddress,ExternalDirectoryObjectId') |
        Where-Object { $_.PrimarySmtpAddress } |
        Sort-Object DisplayName |
        ForEach-Object { [pscustomobject]@{ DisplayName = $_.DisplayName; Address = $_.PrimarySmtpAddress; Id = $_.ExternalDirectoryObjectId } }
}
