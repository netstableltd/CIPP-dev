function Get-CIPPReportPeriod {
    <#
    .SYNOPSIS
        Resolves a report period name to start/end dates and labels.

    .PARAMETER Period
        One of:
        - 'LastMonth' (default): the previous calendar month.
        - 'ThisMonth': the 1st of this month to now.
        - 'yyyy-MM': a calendar month.
        - 'RollingMonth': one month up to the end of yesterday (on 16 November: 16 October - 15 November).
          For reports that go out mid-month.
        - 'LastNDays' (N = 1-366, e.g. 'Last30Days'): the N whole days up to the end of yesterday.
        - 'yyyy-MM-dd_yyyy-MM-dd': any dates, first and last day both included (at most 366 days).
        Dates are whole UTC days. A range that is exactly a calendar month is treated as that month, so it
        shares the month's draft. A range that has not finished yet runs to now and is marked partial.

    .PARAMETER Now
        Reference time (for tests). Defaults to the current UTC time.

    .OUTPUTS
        Key = 'yyyy-MM' for a calendar month, else 'yyyy-MM-dd_yyyy-MM-dd' (first and last day). The key
        always resolves back to the same dates, so drafts can be regenerated from it.
        Label = 'September 2026' or '16 October - 15 November 2026' (+ ' (to date)' when partial).
        Start (UTC, inclusive), End (UTC, exclusive), IsPartial, Kind ('Month' or 'Range'), Days and
        Monthly (true when the period is a month long, so the report is the monthly report).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Period = 'LastMonth',
        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    $Utc = { param([int]$Y, [int]$M, [int]$D) [datetime]::new($Y, $M, $D, 0, 0, 0, [DateTimeKind]::Utc) }
    $ParseDay = {
        param([string]$Text)
        $Parsed = [datetime]::MinValue
        if (-not [datetime]::TryParseExact($Text, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref]$Parsed)) {
            throw "'$Text' is not a valid date."
        }
        & $Utc $Parsed.Year $Parsed.Month $Parsed.Day
    }
    $MonthStart = & $Utc $Now.Year $Now.Month 1
    $Today = & $Utc $Now.Year $Now.Month $Now.Day
    $Kind = 'Month'
    $Partial = $false

    switch -Regex ($Period) {
        '^(LastMonth|)$' {
            $Start = $MonthStart.AddMonths(-1); $End = $MonthStart
        }
        '^ThisMonth$' {
            $Start = $MonthStart; $End = $MonthStart.AddMonths(1)
        }
        '^\d{4}-\d{2}$' {
            $Start = & $ParseDay "$Period-01"; $End = $Start.AddMonths(1)
        }
        '^RollingMonth$' {
            $Kind = 'Range'; $Start = $Today.AddMonths(-1); $End = $Today
        }
        '^Last(\d{1,3})Days$' {
            $Days = [int]$Matches[1]
            if ($Days -lt 1 -or $Days -gt 366) { throw 'A report can cover 1 to 366 days.' }
            $Kind = 'Range'; $Start = $Today.AddDays(-$Days); $End = $Today
        }
        '^(\d{4}-\d{2}-\d{2})_(\d{4}-\d{2}-\d{2})$' {
            $Kind = 'Range'
            $Start = & $ParseDay $Matches[1]
            $End = (& $ParseDay $Matches[2]).AddDays(1)
            if ($End -le $Start) { throw 'The end date must be on or after the start date.' }
            if (($End - $Start).TotalDays -gt 366) { throw 'A report can cover at most 366 days.' }
        }
        default { throw "Unknown report period '$Period'. Use LastMonth, ThisMonth, RollingMonth, LastNDays, yyyy-MM or yyyy-MM-dd_yyyy-MM-dd." }
    }

    if ($Start -gt $Now) { throw 'The report period starts in the future.' }

    # A range that is exactly a calendar month is that month (same key, label and draft).
    if ($Kind -eq 'Range' -and $Start.Day -eq 1 -and $Start.AddMonths(1) -eq $End) { $Kind = 'Month' }

    $Culture = [cultureinfo]::GetCultureInfo('en-GB')
    $LastDay = $End.AddDays(-1)
    $DayCount = [int]($End - $Start).TotalDays
    # Month-long ranges (28-31 days) are still the monthly report.
    $Monthly = $Kind -eq 'Month' -or ($DayCount -ge 28 -and $DayCount -le 31)
    if ($Kind -eq 'Month') {
        $Key = $Start.ToString('yyyy-MM')
        $Label = $Start.ToString('MMMM yyyy', $Culture)
    } else {
        $Key = "$($Start.ToString('yyyy-MM-dd'))_$($LastDay.ToString('yyyy-MM-dd'))"
        $Label = if ($DayCount -eq 1) {
            $Start.ToString('d MMMM yyyy', $Culture)
        } elseif ($Start.Year -ne $LastDay.Year) {
            "$($Start.ToString('d MMMM yyyy', $Culture)) $([char]0x2013) $($LastDay.ToString('d MMMM yyyy', $Culture))"
        } elseif ($Start.Month -ne $LastDay.Month) {
            "$($Start.ToString('d MMMM', $Culture)) $([char]0x2013) $($LastDay.ToString('d MMMM yyyy', $Culture))"
        } else {
            "$($Start.Day) $([char]0x2013) $($LastDay.ToString('d MMMM yyyy', $Culture))"
        }
    }
    # Not finished yet: run to now.
    if ($End -gt $Now) { $Partial = $true; $End = $Now }

    [PSCustomObject]@{
        Key       = $Key
        Label     = $Label + $(if ($Partial) { ' (to date)' } else { '' })
        Start     = $Start
        End       = $End
        IsPartial = $Partial
        Kind      = $Kind
        Days      = $DayCount
        Monthly   = [bool]$Monthly
    }
}
