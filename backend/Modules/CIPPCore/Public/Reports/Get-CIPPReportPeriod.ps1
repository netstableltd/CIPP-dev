function Get-CIPPReportPeriod {
    <#
    .SYNOPSIS
        Resolves a report period name to start/end dates and labels.

    .PARAMETER Period
        'LastMonth' (default - the previous calendar month), 'ThisMonth' (1st of this month to now),
        or a specific month as 'yyyy-MM'.

    .PARAMETER Now
        Reference time (for tests). Defaults to the current UTC time.

    .OUTPUTS
        @{ Key = 'yyyy-MM'; Label = 'September 2026'; Start = [datetime] (UTC, inclusive); End = [datetime] (UTC, exclusive); IsPartial = [bool] }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$Period = 'LastMonth',
        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    $MonthStart = [datetime]::new($Now.Year, $Now.Month, 1, 0, 0, 0, [DateTimeKind]::Utc)
    switch -Regex ($Period) {
        '^(LastMonth|)$' {
            $Start = $MonthStart.AddMonths(-1); $End = $MonthStart; $Partial = $false
        }
        '^ThisMonth$' {
            $Start = $MonthStart; $End = $Now; $Partial = $true
        }
        '^\d{4}-\d{2}$' {
            $Start = [datetime]::ParseExact("$Period-01", 'yyyy-MM-dd', [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::AssumeUniversal -bor [System.Globalization.DateTimeStyles]::AdjustToUniversal)
            $End = $Start.AddMonths(1)
            $Partial = $End -gt $Now
            if ($Partial) { $End = $Now }
        }
        default { throw "Unknown report period '$Period'. Use LastMonth, ThisMonth or yyyy-MM." }
    }

    $Culture = [cultureinfo]::GetCultureInfo('en-GB')
    [PSCustomObject]@{
        Key       = $Start.ToString('yyyy-MM')
        Label     = $Start.ToString('MMMM yyyy', $Culture) + $(if ($Partial) { ' (to date)' } else { '' })
        Start     = $Start
        End       = $End
        IsPartial = $Partial
    }
}
