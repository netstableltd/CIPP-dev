function Invoke-ExecSharedMailboxSummaryPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.Read
    .DESCRIPTION
        Community Additions > Shared mailbox (add-on shared-mailbox): the "your shared mailbox is ready" PDF for a shared mailbox (Identity, its address) in the tenant (tenantFilter): how it is set up, read from the tenant, anything not finished, and a guide for the team on adding it to Outlook, sending from it and working together, matched to the choices made (Answers, as for ExecSharedMailboxSetup). The uploaded step-by-step guide is added at the end unless IncludeGuide is false. Optional ContactName and PreparedBy. Returns application/pdf with the CIPP branding.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $B = $Request.Body
    $TenantFilter = "$($B.tenantFilter ?? $Request.Query.tenantFilter)"
    $Identity = "$($B.Identity)".Trim()
    $ContactName = "$($B.ContactName)".Trim()
    $PreparedBy = "$($B.PreparedBy)".Trim()
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = $Text } }
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose a single tenant.') }
    if (-not $Identity) { return (& $Bad 'Choose the shared mailbox.') }
    if ($ContactName.Length -gt 100 -or $PreparedBy.Length -gt 100) { return (& $Bad 'Names must be 100 characters or fewer.') }
    try { $Answers = Resolve-CIPPSharedMailboxAnswers -Answers $B.Answers } catch { return (& $Bad $_.Exception.Message) }

    try {
        $Status = Get-CIPPSharedMailboxStatus -TenantFilter $TenantFilter -Identity $Identity
        if (-not $Status.Exists) { return (& $Bad "There's no mailbox $Identity.") }
        $Guide = $null
        if ("$($B.IncludeGuide)" -ne 'false') {
            $Stored = Get-CIPPAddonGuide -AddonId 'shared-mailbox' -Key 'sending' -IncludeFile
            if ($Stored) { try { $Guide = ConvertFrom-CIPPDocxGuide -Bytes $Stored.Bytes } catch { Write-Information "The sending guide couldn't be read: $($_.Exception.Message)" } }
        }
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter
        $Tree = Build-CippSharedMailboxSummaryTree -TenantName $TenantName -Status $Status -Answers $Answers -ContactName $ContactName -PreparedBy $PreparedBy -Guide $Guide
        $Zone = try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc }
        $GeneratedOn = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $Zone).ToString('d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Shared mailbox' -GeneratedOn $GeneratedOn
        $FileName = ("Shared_mailbox_$($Status.Address)" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; ContentType = 'application/pdf'; Headers = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }; Body = $Bytes })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $Request.Params.CIPPEndpoint -tenant $TenantFilter -message "Failed to make the shared mailbox summary PDF: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
