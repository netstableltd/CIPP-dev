function Invoke-ListReportDrafts {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.Read
    .DESCRIPTION
        Lists customer report drafts awaiting review, approved or sent (Reports > Review), newest month first. Pass Id (the draft's RowKey) for one draft with its findings, sections and saved changes.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Table = Get-CIPPTable -TableName 'ReportDrafts'
        $Id = "$($Request.Query.Id)"
        if ($Id -and $Id -notmatch '^[0-9a-fA-F-]{36}_\d{4}-\d{2}$') {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Invalid draft id.' } })
        }
        $Filter = if ($Id) { "PartitionKey eq 'Draft' and RowKey eq '$Id'" } else { "PartitionKey eq 'Draft'" }
        $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter $Filter)
        $Rows = @(Test-CIPPReportAccess -Request $Request -Filter $Rows)
        $FromJson = { param($Text, $Default) if ($Text) { try { ConvertFrom-Json -InputObject $Text -Depth 10 } catch { $Default } } else { $Default } }
        $Body = @($Rows | Sort-Object @{ e = { $_.PeriodKey }; Descending = $true }, Company | ForEach-Object {
                $Row = [ordered]@{
                    Id          = $_.RowKey
                    TenantId    = $_.TenantId
                    Tenant      = $_.Tenant
                    Company     = $_.Company
                    PeriodKey   = $_.PeriodKey
                    PeriodLabel = $_.PeriodLabel
                    Status      = $_.Status
                    ReportGUID  = $_.ReportGUID
                    GeneratedAt = $_.GeneratedAt
                    GeneratedBy = $_.GeneratedBy
                    ApprovedBy  = $_.ApprovedBy
                    ApprovedAt  = $_.ApprovedAt
                    SentAt      = $_.SentAt
                    SentTo      = $_.SentTo
                }
                $Findings = @(& $FromJson $_.Findings @())
                $Overrides = & $FromJson $_.Overrides ([pscustomobject]@{})
                $Row.Recommendations = @($Findings | Where-Object { $_.Customer }).Count
                $Row.Changes = @(@($Overrides.HiddenFindings) + @($Overrides.HiddenSections) + @($Overrides.Extra) | Where-Object { $_ }).Count + $(if ($Overrides.FindingText) { @($Overrides.FindingText.PSObject.Properties).Count } else { 0 }) + $(if ($Overrides.FindingItems) { @($Overrides.FindingItems.PSObject.Properties).Count } else { 0 }) + $(if ("$($Overrides.Note)".Trim()) { 1 } else { 0 })
                if ($Id) {
                    $Row.Findings = $Findings
                    $Row.Sections = @(& $FromJson $_.Sections @())
                    $Row.Overrides = $Overrides
                }
                [pscustomobject]$Row
            })
        if ($Id) { $Body = $Body | Select-Object -First 1 }
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list report drafts: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to list report drafts: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
