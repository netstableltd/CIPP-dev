function Invoke-ListSharedMailboxSetup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Community Additions > Shared mailbox (add-on shared-mailbox). Read-only. Returns the questions for the customer with their options and our recommendations (Options), the uploaded step-by-step guide if any (Guide), and either the tenant's shared mailboxes (Mailboxes; no Identity) or how one shared mailbox (Identity, its address) is set up now: who has Full Access, Send As and Send on behalf, the access group, sent-item copies, address book, who can email it, signature rule, size, licence, archive, regional settings, sign-in, and the answers those amount to (Current).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = "$($Request.Query.tenantFilter ?? $Request.Body.tenantFilter)"
    $Identity = "$($Request.Query.Identity ?? $Request.Body.Identity)".Trim()
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Choose a single tenant.' } })
    }
    try {
        $Body = [ordered]@{
            Options = Get-CIPPSharedMailboxOptions
            Guide   = $(try { Get-CIPPAddonGuide -AddonId 'shared-mailbox' -Key 'sending' } catch { $null })
        }
        if ($Identity) { $Body.Status = Get-CIPPSharedMailboxStatus -TenantFilter $TenantFilter -Identity $Identity }
        else { $Body.Mailboxes = @(Get-CIPPSharedMailboxList -TenantFilter $TenantFilter) }
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $Body })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Couldn't read the shared mailbox setup: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Couldn't read the shared mailbox: $($ErrorMessage.NormalizedError)" } })
    }
}
