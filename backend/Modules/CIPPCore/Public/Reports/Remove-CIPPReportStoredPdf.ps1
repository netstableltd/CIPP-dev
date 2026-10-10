function Remove-CIPPReportStoredPdf {
    <#
    .SYNOPSIS
        Deletes a generated report (its ReportBuilderReports row and its PDF, including split part rows).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$ReportGUID)

    if ($ReportGUID -notmatch '^[0-9a-fA-F-]{36}$') { return }
    try {
        $ReportTable = Get-CIPPTable -TableName 'ReportBuilderReports'
        $Report = @(Get-CIPPAzDataTableEntity @ReportTable -Filter "RowKey eq '$ReportGUID'" -Property PartitionKey, RowKey)
        if ($Report.Count -gt 0) { Remove-CIPPAzDataTableEntity @ReportTable -Entity $Report }
        $PdfTable = Get-CIPPTable -TableName 'ReportBuilderPdfs'
        $PdfRows = @(Get-CIPPAzDataTableEntity @PdfTable -Filter "RowKey eq '$ReportGUID' or OriginalEntityId eq '$ReportGUID'" -Property PartitionKey, RowKey)
        if ($PdfRows.Count -gt 0) { Remove-CIPPAzDataTableEntity @PdfTable -Entity $PdfRows }
    } catch {
        Write-Information "Could not remove report $($ReportGUID): $($_.Exception.Message)"
    }
}
