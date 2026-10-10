function ConvertTo-AteraLocalTime {
    <#
    .SYNOPSIS
        Converts a UTC time to local time in a named time zone, even on hosts without time zone data.

    .DESCRIPTION
        Uses the system time zone database when it has the zone. Containers without tz data get a
        built-in rule for UK/Irish/Portuguese and Central European time (EU summer time runs from
        01:00 UTC on the last Sunday of March to 01:00 UTC on the last Sunday of October); any other
        zone falls back to UTC.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][datetime]$Utc,
        [string]$TimeZone = 'Europe/London'
    )
    $Utc = [datetime]::SpecifyKind($Utc, [DateTimeKind]::Utc)
    $Zone = try { [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone) } catch { $null }
    if ($Zone) { return [System.TimeZoneInfo]::ConvertTimeFromUtc($Utc, $Zone) }
    $BaseOffset = switch -Regex ($TimeZone) {
        '^(Europe/(London|Dublin|Lisbon)|GMT Standard Time)$' { 0; break }
        '^(Europe/(Amsterdam|Berlin|Paris|Brussels|Madrid|Rome|Vienna|Zurich|Stockholm|Oslo|Copenhagen|Warsaw|Prague)|W\. Europe Standard Time|Romance Standard Time|Central Europe Standard Time)$' { 1; break }
        default { $null }
    }
    if ($null -eq $BaseOffset) { return $Utc }
    $LastSunday = { param([int]$Year, [int]$Month) $d = [datetime]::new($Year, $Month, [datetime]::DaysInMonth($Year, $Month), 1, 0, 0, [DateTimeKind]::Utc); while ($d.DayOfWeek -ne [DayOfWeek]::Sunday) { $d = $d.AddDays(-1) }; $d }
    $Summer = $Utc -ge (& $LastSunday $Utc.Year 3) -and $Utc -lt (& $LastSunday $Utc.Year 10)
    $Utc.AddHours($BaseOffset + $(if ($Summer) { 1 } else { 0 }))
}
