function Invoke-ExecSharedMailboxCustomerPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Community Additions > Shared mailbox (add-on shared-mailbox): the customer PDF for a new shared mailbox in the tenant (tenantFilter): the choices to make (who gets access and how, sending, Outlook, sent emails, signature, address book, who can email it, size and licence), what each option means with its pros and cons, what we recommend, and what to reply with. Optional MailboxName (the mailbox asked for), ContactName (who it is addressed to) and PreparedBy (who it is from). Returns application/pdf with the CIPP branding.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = "$($Request.Body.tenantFilter ?? $Request.Query.tenantFilter)"
    $MailboxName = "$($Request.Body.MailboxName)".Trim()
    $ContactName = "$($Request.Body.ContactName)".Trim()
    $PreparedBy = "$($Request.Body.PreparedBy)".Trim()
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = $Text } }
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose a single tenant.') }
    if ($ContactName.Length -gt 100 -or $PreparedBy.Length -gt 100 -or $MailboxName.Length -gt 254) { return (& $Bad 'Names must be 100 characters or fewer.') }

    try {
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter
        $Tree = Build-CippSharedMailboxCustomerTree -TenantName $TenantName -MailboxName $MailboxName -ContactName $ContactName -PreparedBy $PreparedBy
        $Zone = try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc }
        $GeneratedOn = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $Zone).ToString('d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Shared mailbox' -GeneratedOn $GeneratedOn
        $FileName = ("Shared_mailbox_choices_$TenantName" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; ContentType = 'application/pdf'; Headers = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }; Body = $Bytes })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Failed to make the shared mailbox customer PDF: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
