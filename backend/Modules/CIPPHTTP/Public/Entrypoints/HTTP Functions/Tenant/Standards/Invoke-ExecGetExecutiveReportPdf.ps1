function Invoke-ExecGetExecutiveReportPdf {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Standards.Read
    .DESCRIPTION
        Server-renders the Executive Summary report as application/pdf bytes. Every figure is read from the
        nightly Reporting DB cache via New-CIPPDbRequest (Users/Guests/Roles for the environment overview,
        LicenseOverview, ManagedDevices, ConditionalAccessPolicies and SecureScore) plus the standards
        comparison from the CippStandardsReports table resolved against the standards catalog - the same
        cached data the rest of CIPP reports from, with no live Graph or cross-endpoint HTTP calls. The
        shaped data is composed through the shared CIPPSharp component kit (Build-CippExecutiveReportTree),
        the server-side replacement for the client react-pdf ExecutiveReportButton. Each source is gathered
        defensively: a source with no cached data simply drops its section.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $TriggerMetadata.FunctionName

    try {
        $TenantFilter = $Request.Query.tenantFilter ?? $Request.Body.tenantFilter
        if ([string]::IsNullOrWhiteSpace($TenantFilter)) {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = 'A tenantFilter is required' })
        }

        # The branding preset a caller picked for this render, else the global branding settings.
        $BrandingPresetId = [string]($Request.Body.brandingPresetId ?? $Request.Query.brandingPresetId)
        $TenantName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId $BrandingPresetId

        $Data = Get-CippExecutiveReportData -TenantFilter $TenantFilter -TenantName $TenantName

        # Optional per-section toggles from the client's section panel (POST body). Absent -> full report.
        $SectionConfig = @{}
        $RawCfg = $Request.Body.sectionConfig
        if ($RawCfg -is [hashtable]) { $SectionConfig = $RawCfg }
        elseif ($RawCfg) { foreach ($p in $RawCfg.PSObject.Properties) { $SectionConfig[$p.Name] = [bool]$p.Value } }

        $Report = Build-CippExecutiveReportTree -Data $Data -SectionConfig $SectionConfig

        # Branding: a named preset if the client selected one (the report's Branding dropdown), else
        # the tenant/global default.
        $Bytes = ConvertTo-CippReportPdf -Blocks $Report.Blocks -Variables $Report.Variables -TenantName $TenantName -TenantFilter $TenantFilter `
            -ReportName 'Executive Summary' -BrandingPresetId $BrandingPresetId

        $FileName = ("Executive_Report_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'
        return ([HttpResponseContext]@{
                StatusCode  = [HttpStatusCode]::OK
                ContentType = 'application/pdf'
                Headers     = @{ 'Content-Disposition' = "inline; filename=`"$FileName`"" }
                Body        = $Bytes
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -Headers $Request.Headers -API $APIName -message "Failed to render Executive report: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = "Error: $($ErrorMessage.NormalizedError)" })
    }
}
