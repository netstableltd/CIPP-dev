function Get-CIPPReportSettings {
    <#
    .SYNOPSIS
        Returns the global Reports settings, with defaults applied for anything not yet saved.

    .DESCRIPTION
        Global settings for the Reports area (scheduled internal pre-check and customer reports).
        Stored as a single row in the ReportSettings table (PartitionKey 'Settings', RowKey 'Global').
        Per-company settings override these and are stored separately.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Defaults = [ordered]@{
        PrecheckRecipients    = ''               # comma-separated addresses that receive the internal pre-check
        ReportDayMode         = 'FirstWorkingDay' # FirstWorkingDay | DayOfMonth
        ReportDay             = 1                # used when ReportDayMode = DayOfMonth (1-28)
        PrecheckLeadDays      = 5                # pre-check runs this many days before the report day
        SendTime              = '09:00'          # local time, HH:mm
        TimeZone              = 'Europe/London'  # IANA or Windows time zone id
        DefaultDeliveryMode   = 'Review'         # Review | Auto | Manual
        CustomerSendEnabled   = $false           # master switch: when off, nothing is ever sent to customer recipients
    }

    $Table = Get-CIPPTable -TableName 'ReportSettings'
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Settings' and RowKey eq 'Global'"

    $Settings = [ordered]@{}
    foreach ($Key in $Defaults.Keys) {
        $Value = if ($Row -and $null -ne $Row.$Key -and "$($Row.$Key)" -ne '') { $Row.$Key } else { $Defaults[$Key] }
        $Settings[$Key] = $Value
    }
    $Settings.ReportDay = [int]$Settings.ReportDay
    $Settings.PrecheckLeadDays = [int]$Settings.PrecheckLeadDays
    $Settings.CustomerSendEnabled = [System.Convert]::ToBoolean($Settings.CustomerSendEnabled)
    $Settings.LastModified = if ($Row) { $Row.Timestamp } else { $null }
    $Settings.LastModifiedBy = if ($Row) { $Row.ModifiedBy } else { $null }

    return [PSCustomObject]$Settings
}
