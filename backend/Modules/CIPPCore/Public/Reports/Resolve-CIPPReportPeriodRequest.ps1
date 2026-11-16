function Resolve-CIPPReportPeriodRequest {
    <#
    .SYNOPSIS
        Works out the report period asked for in a Reports request (draft or test run).

    .DESCRIPTION
        Period can be any value Get-CIPPReportPeriod accepts, or:
        - 'Scheduled' (or blank): the company's usual period ("Report covers" in Reports > Companies),
          else the default in Reports > Settings, else LastMonth.
        - 'Custom': StartDate and EndDate from the request (both days included). Dates may be unix seconds
          (the date picker) or yyyy-MM-dd; unix seconds are read in the reports time zone.
        Returns the period as Get-CIPPReportPeriod takes it. Throws a message fit to show the user when the
        period is not valid.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $Body,
        [string]$TenantId,
        $Settings,
        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    $Value = {
        param($Field)
        if ($null -eq $Field) { return '' }
        if ($Field -is [System.Collections.IDictionary]) { if ($Field.Contains('value')) { return "$($Field['value'])" }; return "$Field" }
        if ($Field.PSObject.Properties.Name -contains 'value') { return "$($Field.value)" }
        "$Field"
    }
    if ($null -eq $Settings) { $Settings = Get-CIPPReportSettings }

    $Period = (& $Value $Body.Period).Trim()

    if ($Period -eq '' -or $Period -eq 'Scheduled') {
        $Period = ''
        if ($TenantId) {
            try {
                $Table = Get-CIPPTable -TableName 'ReportCompanies'
                $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Company' and RowKey eq '$TenantId'" | Select-Object -First 1
                if ($Row -and "$($Row.ReportPeriod)" -and "$($Row.ReportPeriod)" -ne 'Default') { $Period = "$($Row.ReportPeriod)" }
            } catch {}
        }
        if (-not $Period) { $Period = "$($Settings.DefaultReportPeriod)" }
        if (-not $Period) { $Period = 'LastMonth' }
    }

    if ($Period -eq 'Custom') {
        $Zone = $null
        try { $Zone = [System.TimeZoneInfo]::FindSystemTimeZoneById("$($Settings.TimeZone)") } catch {}
        $ToDay = {
            param($Field, $Name)
            $Raw = (& $Value $Field).Trim()
            if (-not $Raw) { throw "Choose a $Name date." }
            if ($Raw -match '^\d{9,13}$') {
                $Seconds = [int64]$Raw
                if ($Raw.Length -gt 11) { $Seconds = [int64]($Seconds / 1000) }
                $Moment = [DateTimeOffset]::FromUnixTimeSeconds($Seconds).UtcDateTime
                if ($Zone) { $Moment = [System.TimeZoneInfo]::ConvertTimeFromUtc($Moment, $Zone) }
                return $Moment.ToString('yyyy-MM-dd')
            }
            $Parsed = [datetime]::MinValue
            if ([datetime]::TryParseExact($Raw, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed) -or
                [datetime]::TryParse($Raw, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
                return $Parsed.ToString('yyyy-MM-dd')
            }
            throw "The $Name date '$Raw' is not a date."
        }
        $Period = "$(& $ToDay $Body.StartDate 'start')_$(& $ToDay $Body.EndDate 'end')"
    }

    # Throws a readable message when the period is not valid.
    $null = Get-CIPPReportPeriod -Period $Period -Now $Now
    return $Period
}
