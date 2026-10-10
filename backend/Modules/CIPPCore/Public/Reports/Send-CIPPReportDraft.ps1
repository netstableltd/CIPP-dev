function Send-CIPPReportDraft {
    <#
    .SYNOPSIS
        Emails an approved customer report draft to the company's report recipients.

    .DESCRIPTION
        Sends the approved PDF itself (the one reviewed on screen), one message per recipient, then marks
        the draft Sent. Refuses unless the draft is Approved, "Allow sending reports to customer
        recipients" is on in Reports > Settings, and the company has recipients.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RowKey,
        [string]$RequestedBy = 'CIPP',
        $Headers
    )

    $Table = Get-CIPPTable -TableName 'ReportDrafts'
    $Draft = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Draft' and RowKey eq '$RowKey'" | Select-Object -First 1
    if (-not $Draft) { throw 'Draft not found.' }
    if ($Draft.Status -eq 'Sent') { throw "This report was already sent on $($Draft.SentAt)." }
    if ($Draft.Status -ne 'Approved') { throw 'Approve the draft before sending it.' }

    $Settings = Get-CIPPReportSettings
    if (-not $Settings.CustomerSendEnabled) {
        throw 'Sending to customers is switched off (Reports > Settings > Allow sending reports to customer recipients).'
    }
    $Company = @(Get-CIPPReportCompanies -TenantId $Draft.TenantId) | Select-Object -First 1
    $Recipients = @("$($Company.Recipients)" -split '[,;\s]+' | Where-Object { $_ -match '^[^@\s]+@[^@\s]+\.[^@\s]+$' })
    if ($Recipients.Count -eq 0) { throw "$($Draft.Company) has no report recipients (Reports > Companies)." }

    $PdfTable = Get-CIPPTable -TableName 'ReportBuilderPdfs'
    $Pdf = Get-CIPPAzDataTableEntity @PdfTable -Filter "RowKey eq '$($Draft.ReportGUID)'" | Select-Object -First 1
    if (-not $Pdf -or -not $Pdf.Pdf) { throw 'The approved PDF could not be found. Regenerate the draft and approve it again.' }

    $Subject = "$($Draft.Company) $([char]0x2014) Monthly IT Report $([char]0x2014) $($Draft.PeriodLabel)"
    $Html = '<p>Please find attached the monthly IT report for {0} covering {1}.</p><p>If you would like to talk any of it through, just reply to this email.</p>' -f [System.Net.WebUtility]::HtmlEncode($Draft.Company), [System.Net.WebUtility]::HtmlEncode($Draft.PeriodLabel)
    $FileName = if ($Draft.FileName) { "$($Draft.FileName)" } else { "$($Pdf.FileName)" }
    $Attachment = @(@{ Name = $FileName; ContentType = 'application/pdf'; ContentBytes = "$($Pdf.Pdf)" })

    $Sent = [System.Collections.Generic.List[string]]::new()
    $Failed = [System.Collections.Generic.List[string]]::new()
    foreach ($Address in $Recipients) {
        try {
            $null = Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $Html -TenantFilter $Draft.Tenant -altEmail $Address -Attachments $Attachment -APIName 'Reports'
            $Sent.Add($Address)
        } catch { $Failed.Add("$Address ($($_.Exception.Message))") }
    }
    if ($Sent.Count -gt 0) {
        $Update = @{}
        foreach ($P in $Draft.PSObject.Properties) { if ($P.Name -notin @('Timestamp', 'ETag') -and $P.Name -notlike 'odata*') { $Update[$P.Name] = $P.Value } }
        $Update.Status = 'Sent'
        $Update.SentAt = (Get-Date).ToUniversalTime().ToString('o')
        $Update.SentTo = ($Sent -join ', ')
        $Update.SentBy = "$RequestedBy"
        Add-CIPPAzDataTableEntity @Table -Entity $Update -Force | Out-Null
    }
    $Message = if ($Sent.Count -gt 0) { "$($Draft.PeriodLabel) report for $($Draft.Company) sent to $($Sent -join ', ')." } else { "The $($Draft.PeriodLabel) report for $($Draft.Company) was not sent." }
    if ($Failed.Count -gt 0) { $Message += " Failed: $($Failed -join '; ')." }
    Write-LogMessage -headers $Headers -API 'Reports' -tenant $Draft.Tenant -tenantId $Draft.TenantId -message $Message -Sev $(if ($Failed.Count -gt 0) { 'Warning' } else { 'Info' })
    [pscustomobject]@{ Results = $Message; Sent = @($Sent) }
}
