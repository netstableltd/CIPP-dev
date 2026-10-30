function Invoke-ExecClaudeConnectorCustomerPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Community Additions > Claude for Microsoft 365 (add-on claude-m365): the customer information PDF for the tenant (tenantFilter). Explains the options for giving Claude access to Microsoft 365, what we recommend having first (third-party backup, Entra ID P1, Microsoft Defender, Business Premium) filled in from the tenant, the four access levels with pros and cons, and what to reply with. Optional ContactName (who it is addressed to) and PreparedBy (who it is from). Returns application/pdf with the CIPP branding.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = "$($Request.Body.tenantFilter ?? $Request.Query.tenantFilter)"
    $ContactName = "$($Request.Body.ContactName)".Trim()
    $PreparedBy = "$($Request.Body.PreparedBy)".Trim()
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = $Text } }

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose a single tenant.') }
    if ($ContactName.Length -gt 100 -or $PreparedBy.Length -gt 100) { return (& $Bad 'Names must be 100 characters or fewer.') }

    try {
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter
        $Readiness = Get-CIPPClaudeConnectorReadiness -TenantFilter $TenantFilter
        $Tree = Build-CippClaudeConnectorCustomerTree -TenantName $TenantName -Readiness $Readiness -ContactName $ContactName -PreparedBy $PreparedBy
        $Zone = try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc }
        $GeneratedOn = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $Zone).ToString('d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'Claude for Microsoft 365' -GeneratedOn $GeneratedOn
        $FileName = ("Claude_for_Microsoft_365_$TenantName" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to make the Claude customer PDF: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
