function Invoke-ExecChatGPTConnectorSummaryPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Community Additions > ChatGPT for Microsoft 365 (add-on chatgpt-m365): the end-of-setup summary PDF for the tenant (tenantFilter). Read from the tenant: who can use ChatGPT and at what level, what ChatGPT can read, the safeguards in place, anything not finished, and what happens next. GroupName is the access group (default SG-ChatGPT-Users). Optional ContactName (who it is addressed to) and PreparedBy (who it is from). The uploaded connection guide (ExecAddonGuide, AddonId chatgpt-m365, Key connection) is added at the end unless IncludeGuide is false. Returns application/pdf with the CIPP branding.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $TenantFilter = "$($Request.Body.tenantFilter ?? $Request.Query.tenantFilter)"
    $ContactName = "$($Request.Body.ContactName)".Trim()
    $PreparedBy = "$($Request.Body.PreparedBy)".Trim()
    $GroupName = "$($Request.Body.GroupName)".Trim()
    if (-not $GroupName) { $GroupName = 'SG-ChatGPT-Users' }
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = $Text } }

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose a single tenant.') }
    if ($ContactName.Length -gt 100 -or $PreparedBy.Length -gt 100) { return (& $Bad 'Names must be 100 characters or fewer.') }
    if ($GroupName -notmatch '^[A-Za-z0-9 _.\-]{1,120}$') { return (& $Bad 'The group name can only use letters, numbers, spaces, dots, dashes and underscores (up to 120).') }

    try {
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter
        $Status = Get-CIPPChatGPTConnectorStatus -TenantFilter $TenantFilter -GroupName $GroupName
        $Zone = try { [TimeZoneInfo]::FindSystemTimeZoneById([string]$env:CIPP_TIMEZONE) } catch { [TimeZoneInfo]::Utc }
        $GeneratedOn = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $Zone).ToString('d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))
        # The uploaded connection guide goes at the end unless IncludeGuide is false.
        $Guide = $null
        if ("$($Request.Body.IncludeGuide)" -ne 'false') {
            $Stored = Get-CIPPAddonGuide -AddonId 'chatgpt-m365' -Key 'connection' -IncludeFile
            if ($Stored) {
                try { $Guide = ConvertFrom-CIPPDocxGuide -Bytes $Stored.Bytes }
                catch { Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "The ChatGPT connection guide couldn't be read and was left out: $($_.Exception.Message)" -Sev Warning }
            }
        }
        $Tree = Build-CippChatGPTConnectorSummaryTree -TenantName $TenantName -Status $Status -ContactName $ContactName -PreparedBy $PreparedBy -GeneratedOn $GeneratedOn -Guide $Guide
        $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $TenantName -TenantFilter $TenantFilter -ReportName 'ChatGPT setup summary' -GeneratedOn $GeneratedOn
        $FileName = ("ChatGPT_setup_summary_$TenantName" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Failed to make the ChatGPT setup summary PDF: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
