function New-CIPPReportDraft {
    <#
    .SYNOPSIS
        Generates (or regenerates) the customer report for one company and month as a draft for review.

    .DESCRIPTION
        The draft is the customer report exactly as it would be sent, stored under Generated Reports
        and recorded in the ReportDrafts table (PartitionKey 'Draft', RowKey '<customerId>_<yyyy-MM>')
        with:

          Status       Draft | Approved | Sent
          Overrides    manual changes made on Reports > Review (Resolve-CIPPReportOverrides); kept
                       when the draft is regenerated
          Findings     the pre-check findings before any changes, so the review page can show the
                       original wording next to edits
          Sections     the planned sections, before any were hidden for this month
          ReportGUID   the PDF currently awaiting approval

        Regenerating replaces the previous draft PDF and resets an approval: what is approved is
        always the PDF on screen. A draft that has been sent is not regenerated (throws).

    .PARAMETER Overrides
        New overrides to save with the draft. Omit to keep the saved ones.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [string]$Period = 'LastMonth',
        $Overrides,
        [string]$RequestedBy = 'CIPP',
        $Headers
    )

    $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter } | Select-Object -First 1
    if (-not $Tenant) { throw "Unknown tenant '$TenantFilter'." }
    $PeriodInfo = Get-CIPPReportPeriod -Period $Period

    $Table = Get-CIPPTable -TableName 'ReportDrafts'
    $RowKey = "$($Tenant.customerId)_$($PeriodInfo.Key)"
    $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Draft' and RowKey eq '$RowKey'" | Select-Object -First 1
    if ($Existing -and $Existing.Status -eq 'Sent') {
        throw "The $($PeriodInfo.Label) report for $($Tenant.displayName) has already been sent."
    }
    if ($null -eq $Overrides -and $Existing -and $Existing.Overrides) {
        $Overrides = $Existing.Overrides | ConvertFrom-Json -AsHashtable -ErrorAction SilentlyContinue
    }
    if ($null -eq $Overrides) { $Overrides = @{} }

    $Result = Invoke-CIPPReportGeneration -TenantFilter $Tenant.defaultDomainName -ReportType 'Customer' -Period $PeriodInfo.Key -Draft -Overrides $Overrides -RequestedBy $RequestedBy -Headers $Headers

    # The superseded draft PDF is no longer needed.
    if ($Existing -and $Existing.ReportGUID -and $Existing.ReportGUID -ne $Result.ReportGUID) {
        Remove-CIPPReportStoredPdf -ReportGUID "$($Existing.ReportGUID)"
    }

    $FindingRows = @($Result.Findings | ForEach-Object {
            @{ Id = "$($_.Id)"; Severity = "$($_.Severity)"; Area = "$($_.Area)"; Title = "$($_.Title)"; Detail = "$($_.Detail)"; Customer = "$($_.Customer)"; CustomerItems = @($_.CustomerItems | ForEach-Object { "$_" }) }
        })
    $Entity = @{
        PartitionKey = 'Draft'
        RowKey       = $RowKey
        TenantId     = [string]$Tenant.customerId
        Tenant       = [string]$Tenant.defaultDomainName
        Company      = [string]$Result.TenantName
        PeriodKey    = [string]$PeriodInfo.Key
        PeriodLabel  = [string]$PeriodInfo.Label
        Status       = 'Draft'
        ReportGUID   = [string]$Result.ReportGUID
        FileName     = [string]$Result.FileName
        Overrides    = [string](ConvertTo-Json -InputObject $Overrides -Depth 6 -Compress)
        Findings     = [string](ConvertTo-Json -InputObject @($FindingRows) -Depth 6 -Compress)
        Sections     = [string](ConvertTo-Json -InputObject @($Result.Sections) -Compress)
        GeneratedAt  = (Get-Date).ToUniversalTime().ToString('o')
        GeneratedBy  = [string]$RequestedBy
        ApprovedBy   = ''
        ApprovedAt   = ''
        SentAt       = ''
        SentTo       = ''
    }
    Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null

    [pscustomobject]@{
        Results    = "Draft of the $($PeriodInfo.Label) report for $($Result.TenantName) is ready for review."
        RowKey     = $RowKey
        ReportGUID = $Result.ReportGUID
        Link       = $Result.Link
    }
}
