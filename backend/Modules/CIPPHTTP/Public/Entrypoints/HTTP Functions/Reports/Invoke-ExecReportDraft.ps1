function Invoke-ExecReportDraft {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.ReadWrite
    .DESCRIPTION
        Works with customer report drafts (Reports > Review). Action: Generate (TenantId + Period; creates or regenerates the draft, with Overrides when given), Approve, Reopen (back to draft), Send (emails the approved PDF to the company's recipients; needs "Allow sending" on in Reports > Settings) or Discard. Id is the draft's id for the last four.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body
    $Respond = { param($Code, $Text) [HttpResponseContext]@{ StatusCode = $Code; Body = @{ Results = $Text } } }

    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }

    $Action = "$($Body.Action)"
    $Table = Get-CIPPTable -TableName 'ReportDrafts'

    if ($Action -eq 'Generate') {
        $TenantId = "$($Body.TenantId.value ?? $Body.TenantId)"
        $Period = "$($Body.Period.value ?? $Body.Period)"
        if (-not $Period) { $Period = 'LastMonth' }
        if ($Period -notmatch '^(LastMonth|ThisMonth|\d{4}-\d{2})$') { return (& $Respond ([HttpStatusCode]::BadRequest) 'Period must be LastMonth, ThisMonth or yyyy-MM.') }
        $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -eq $TenantId -or $_.defaultDomainName -eq $TenantId } | Select-Object -First 1
        if (-not $Tenant) { return (& $Respond ([HttpStatusCode]::BadRequest) "Unknown tenant '$TenantId'.") }
        if (-not (Test-CIPPReportAccess -Request $Request -Tenant $Tenant)) { return (& $Respond ([HttpStatusCode]::Forbidden) 'You do not have access to this tenant.') }

        $Overrides = $null
        if ($null -ne $Body.Overrides) {
            $O = $Body.Overrides
            $Errors = [System.Collections.Generic.List[string]]::new()
            $Note = "$($O.Note)".Trim()
            if ($Note.Length -gt 2000) { $Errors.Add('The note must be 2,000 characters or fewer.') }
            $HiddenSections = @($O.HiddenSections | Where-Object { $_ } | ForEach-Object { "$_" })
            foreach ($S in $HiddenSections) { if (-not (Test-CIPPReportSectionId $S)) { $Errors.Add("'$S' is not a known report section.") } }
            $HiddenFindings = @($O.HiddenFindings | Where-Object { $_ } | ForEach-Object { "$_" } | Where-Object { $_ -match '^[\w-]{1,64}$' })
            $Text = @{}
            if ($O.FindingText) {
                foreach ($P in $O.FindingText.PSObject.Properties) {
                    if ($P.Name -notmatch '^[\w-]{1,64}$') { continue }
                    $V = "$($P.Value)".Trim()
                    if ($V.Length -gt 1000) { $Errors.Add('Each recommendation must be 1,000 characters or fewer.') } elseif ($V) { $Text[$P.Name] = $V }
                }
            }
            $Items = @{}
            if ($O.FindingItems) {
                foreach ($P in $O.FindingItems.PSObject.Properties) {
                    if ($P.Name -notmatch '^[\w-]{1,64}$') { continue }
                    $Items[$P.Name] = @(@(if ($P.Value -is [string]) { $P.Value -split '\s*,\s*' } else { @($P.Value) }) | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Select-Object -First 100)
                }
            }
            $Extra = @($O.Extra | Where-Object { "$($_.text)".Trim() } | ForEach-Object { @{ text = "$($_.text)".Trim(); plan = [bool]$_.plan } })
            if ($Extra.Count -gt 10) { $Errors.Add('Add at most 10 recommendations.') }
            if (@($Extra | Where-Object { $_.text.Length -gt 1000 }).Count -gt 0) { $Errors.Add('Each recommendation must be 1,000 characters or fewer.') }
            if ($Errors.Count -gt 0) { return (& $Respond ([HttpStatusCode]::BadRequest) (($Errors | Select-Object -Unique) -join ' ')) }
            $Overrides = @{ Note = $Note; HiddenSections = $HiddenSections; HiddenFindings = $HiddenFindings; FindingText = $Text; FindingItems = $Items; Extra = $Extra }
        }
        try {
            $Result = New-CIPPReportDraft -TenantFilter $Tenant.defaultDomainName -Period $Period -Overrides $Overrides -RequestedBy $User -Headers $Headers
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = $Result.Results; Id = $Result.RowKey; ReportGUID = $Result.ReportGUID } })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -message "Report draft failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            return (& $Respond ([HttpStatusCode]::InternalServerError) "Report draft failed: $($ErrorMessage.NormalizedError)")
        }
    }

    $Id = "$($Body.Id)"
    if ($Id -notmatch '^[0-9a-fA-F-]{36}_\d{4}-\d{2}$') { return (& $Respond ([HttpStatusCode]::BadRequest) 'Invalid draft id.') }
    $Draft = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Draft' and RowKey eq '$Id'" | Select-Object -First 1
    if (-not $Draft) { return (& $Respond ([HttpStatusCode]::NotFound) 'Draft not found.') }
    $Tenant = [pscustomobject]@{ customerId = $Draft.TenantId }
    if (-not (Test-CIPPReportAccess -Request $Request -Tenant $Tenant)) { return (& $Respond ([HttpStatusCode]::NotFound) 'Draft not found.') }

    $Save = {
        param([hashtable]$Changes)
        $Update = @{}
        foreach ($P in $Draft.PSObject.Properties) { if ($P.Name -notin @('Timestamp', 'ETag') -and $P.Name -notlike 'odata*') { $Update[$P.Name] = $P.Value } }
        foreach ($K in $Changes.Keys) { $Update[$K] = $Changes[$K] }
        Add-CIPPAzDataTableEntity @Table -Entity $Update -Force | Out-Null
    }

    try {
        switch ($Action) {
            'Approve' {
                if ($Draft.Status -ne 'Draft') { return (& $Respond ([HttpStatusCode]::Conflict) "This report is already $("$($Draft.Status)".ToLower()).") }
                & $Save @{ Status = 'Approved'; ApprovedBy = "$User"; ApprovedAt = (Get-Date).ToUniversalTime().ToString('o') }
                $Message = "Approved the $($Draft.PeriodLabel) report for $($Draft.Company)."
            }
            'Reopen' {
                if ($Draft.Status -ne 'Approved') { return (& $Respond ([HttpStatusCode]::Conflict) 'Only an approved report can be reopened.') }
                & $Save @{ Status = 'Draft'; ApprovedBy = ''; ApprovedAt = '' }
                $Message = "Reopened the $($Draft.PeriodLabel) report for $($Draft.Company) for changes."
            }
            'Send' {
                $Message = (Send-CIPPReportDraft -RowKey $Id -RequestedBy $User -Headers $Headers).Results
            }
            'Discard' {
                if ($Draft.Status -eq 'Sent') { return (& $Respond ([HttpStatusCode]::Conflict) 'A sent report cannot be discarded.') }
                if ($Draft.ReportGUID) { Remove-CIPPReportStoredPdf -ReportGUID "$($Draft.ReportGUID)" }
                Remove-AzDataTableEntity @Table -Entity $Draft -Force | Out-Null
                $Message = "Discarded the $($Draft.PeriodLabel) draft for $($Draft.Company)."
            }
            default { return (& $Respond ([HttpStatusCode]::BadRequest) 'Action must be Generate, Approve, Reopen, Send or Discard.') }
        }
        if ($Action -ne 'Send') { Write-LogMessage -headers $Headers -API $APIName -tenant $Draft.Tenant -message $Message -Sev 'Info' }
        return (& $Respond ([HttpStatusCode]::OK) $Message)
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return (& $Respond ([HttpStatusCode]::BadRequest) $ErrorMessage.NormalizedError)
    }
}
