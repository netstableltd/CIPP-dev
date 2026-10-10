function Get-AteraMemoryPressure {
    <#
    .SYNOPSIS
        Finds devices whose memory ran above a threshold during working hours, from Atera memory alerts.

    .DESCRIPTION
        Atera's memory alert message carries the usage and the processes using it, e.g.
        "The Memory Usage 95.90% is greater than the threshold of 95.00% for 9.00 minutes. Top 3
        processes triggering the alert: chrome: 5,158.34 MB, svchost: 1,522.61 MB and Spotify: ...".
        An alert counts when the usage in the message is above -Threshold and it was raised on a weekday
        between -WorkdayStart and -WorkdayEnd in -TimeZone.

        Returns one object per device: DeviceGuid, DeviceName, Days (distinct working days), Alerts,
        PeakPercent, TopProcess (the process most often first in the list).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Alerts = @(),
        [double]$Threshold = 90,
        [string]$TimeZone = 'Europe/London',
        [int]$WorkdayStart = 8,
        [int]$WorkdayEnd = 18,
        [datetime]$From = [datetime]::MinValue,
        [datetime]$To = [datetime]::MaxValue
    )

    $Hits = foreach ($Alert in $Alerts) {
        if ("$($Alert.Title)" -notmatch 'Memory') { continue }
        $Message = "$($Alert.AlertMessage)"
        if ($Message -notmatch 'Memory Usage\s+([\d.]+)\s*%') { continue }
        $Usage = [double]::Parse($Matches[1], [cultureinfo]::InvariantCulture)
        if ($Usage -le $Threshold) { continue }
        $Created = $null
        if ($Alert.Created -is [datetime]) { $Created = $Alert.Created.ToUniversalTime() }
        else { $p = [datetime]::MinValue; if ([datetime]::TryParse("$($Alert.Created)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$p)) { $Created = $p } }
        if (-not $Created -or $Created -lt $From -or $Created -ge $To) { continue }
        $Local = ConvertTo-AteraLocalTime -Utc $Created -TimeZone $TimeZone
        if ($Local.DayOfWeek -in @([DayOfWeek]::Saturday, [DayOfWeek]::Sunday)) { continue }
        if ($Local.Hour -lt $WorkdayStart -or $Local.Hour -ge $WorkdayEnd) { continue }
        $Top = if ($Message -match 'processes triggering the alert:\s*([^:]+):') { $Matches[1].Trim() } else { '' }
        [pscustomobject]@{ Key = $(if ($Alert.DeviceGuid) { "$($Alert.DeviceGuid)" } else { "name:$($Alert.DeviceName)" }); DeviceGuid = "$($Alert.DeviceGuid)"; DeviceName = "$($Alert.DeviceName)"; Day = $Local.ToString('yyyy-MM-dd'); Usage = $Usage; Top = $Top }
    }
    foreach ($Group in (@($Hits) | Where-Object { $_ } | Group-Object Key)) {
        $First = $Group.Group[0]
        [pscustomobject]@{
            DeviceGuid  = $First.DeviceGuid
            DeviceName  = $First.DeviceName
            Days        = @($Group.Group | ForEach-Object { $_.Day } | Sort-Object -Unique).Count
            Alerts      = $Group.Count
            PeakPercent = [math]::Round((@($Group.Group | ForEach-Object { $_.Usage }) | Measure-Object -Maximum).Maximum)
            TopProcess  = "$(@($Group.Group | Where-Object Top | Group-Object Top | Sort-Object Count -Descending | Select-Object -First 1).Name)"
        }
    }
}
