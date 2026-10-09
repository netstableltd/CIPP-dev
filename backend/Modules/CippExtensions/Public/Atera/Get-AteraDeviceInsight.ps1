function Get-AteraDeviceInsight {
    <#
    .SYNOPSIS
        Adds plain-English health insights to Atera agents: update status, Windows support, hardware tier,
        disk, restarts and recurring resource alerts.

    .DESCRIPTION
        Atera's API gives the raw agent record (OS build, CPU, RAM, disks, last seen, last reboot) but no
        patch or health verdicts. This works them out so a report, the pre-check and the Report Builder
        can all use the same answers. Every field added is a simple value, so it also works as a Report
        Builder column, filter or chart field.

        UpdateStatus      'Up to date' | 'Behind' | 'Unknown'. Compares the device's Windows build revision
                          (26200.9457 -> 9457) with the newest revision that at least 40% of recently seen
                          devices (last 14 days) in the same servicing family have reached, across the WHOLE
                          Atera account (the fleet). Builds that receive the same monthly updates are pooled
                          (24H2/25H2/26H2 = 26100/26200/26300; 22H2/23H2; Windows 10 2004-22H2). The 40% rule
                          means an optional preview update a few devices installed early does not mark the
                          rest as behind, and the reference moves once most devices take a new month's update.
                          A device within 50 revisions of the reference counts as up to date (out-of-band
                          fixes and previews are small steps; a missed month is a bigger jump).
                          Needs 2+ recently seen devices in the family.
        LatestBuild       That fleet reference on the device's own build, e.g. '26200.9457'.
        WindowsSupport    'Supported' | 'Ending soon' (within 90 days) | 'Unsupported' | 'Unknown', from
                          Config/WindowsLifecycle.json by build and edition (Home/Pro, Enterprise, LTSC, Server).
        WindowsSupportEnds yyyy-MM-dd, or '' when not known.
        WindowsVersion    e.g. 'Windows 11 25H2'.
        IsHomeEdition     $true for Windows Home (not suitable for business: no domain/Entra join, no BitLocker
                          management).
        MemoryGB, CpuSummary, CpuYear (approximate launch year), Windows11Ready ('Yes'|'No'|'Unknown')
        HardwareTier      'Good' | 'Limited' | 'Weak', with HardwareNotes giving the reasons. Weak = 4 GB RAM or
                          less, 2 cores or fewer, a CPU too old for Windows 11 or 10+ years old, or two of the
                          lesser limits together (8 GB RAM, entry-level i3/Ryzen 3/Celeron/Pentium, CPU 7+ years old).
        SystemDiskFreePercent, SystemDiskFreeGB
        DaysSinceSeen, DaysSinceReboot
        AlertCount, ResourceAlertDays (distinct days with CPU or memory alerts), DiskAlertDays - over the
                          alerts passed in (the sync passes 90 days).
        HealthStatus      'Good' | 'Check' | 'Needs attention', with HealthNotes giving the reasons.

    .PARAMETER Agents
        Every agent in the Atera account. The fleet is needed for UpdateStatus; insights are returned for
        all of them (filter afterwards).

    .PARAMETER Alerts
        Alerts to count per device (matched on DeviceGuid, else AgentId).

    .PARAMETER Now
        The time to measure ages from (UTC). Defaults to now.

    .PARAMETER Lifecycle
        Parsed WindowsLifecycle.json. Read from the Config folder when omitted.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Agents = @(),
        [AllowEmptyCollection()][object[]]$Alerts = @(),
        [datetime]$Now = (Get-Date).ToUniversalTime(),
        $Lifecycle
    )

    if (-not $Lifecycle) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
        $Path = Join-Path (Join-Path $Root 'Config') 'WindowsLifecycle.json'
        $Lifecycle = try { Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json } catch { $null }
    }
    $Builds = @(if ($Lifecycle) { $Lifecycle.builds | Sort-Object { [int]$_.build } })
    $NewestKnownBuild = if ($Builds.Count -gt 0) { [int]$Builds[-1].build } else { 0 }

    $ToDate = {
        param($Value)
        if ($null -eq $Value -or "$Value" -eq '') { return $null }
        if ($Value -is [datetime]) { return $Value.ToUniversalTime() }
        $Parsed = [datetime]::MinValue
        if ([datetime]::TryParse("$Value", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$Parsed)) { return $Parsed }
        $null
    }
    $SplitBuild = {
        param($OSBuild)
        if ("$OSBuild" -match '^(\d{4,5})\.(\d+)') { return @([int]$Matches[1], [int]$Matches[2]) }
        if ("$OSBuild" -match '^(\d{4,5})$') { return @([int]$Matches[1], $null) }
        @($null, $null)
    }

    # --- Fleet reference: per servicing family, the newest revision 40% of recent devices have reached ---
    $FamilyOf = {
        param([int]$Build)
        if ($Build -in @(26100, 26200, 26300)) { return 'w11-ge' }
        if ($Build -in @(22621, 22631)) { return 'w11-ni' }
        if ($Build -ge 19041 -and $Build -le 19045) { return 'w10-vb' }
        "$Build"
    }
    $Recent = @($Agents | Where-Object {
            $Seen = & $ToDate $_.LastSeen
            $Seen -and ($Now - $Seen).TotalDays -le 14
        })
    $Reference = @{}
    foreach ($Group in ($Recent | ForEach-Object {
                $Parts = & $SplitBuild $_.OSBuild
                if ($null -ne $Parts[0] -and $null -ne $Parts[1]) { [pscustomobject]@{ Family = (& $FamilyOf $Parts[0]); Revision = $Parts[1] } }
            } | Group-Object Family)) {
        $Total = $Group.Count
        if ($Total -lt 2) { continue }
        $Needed = [math]::Max(2, [math]::Ceiling($Total * 0.4))
        $Revisions = @($Group.Group | ForEach-Object { $_.Revision } | Sort-Object -Descending)
        # The newest revision R with at least $Needed devices on R or later.
        $Reference[$Group.Name] = $Revisions[$Needed - 1]
    }

    # --- Alerts per device --------------------------------------------------------------------------
    $AlertsByDevice = @{}
    foreach ($Alert in $Alerts) {
        $Key = if ($Alert.DeviceGuid) { "g:$($Alert.DeviceGuid)" } elseif ($Alert.AgentId) { "a:$($Alert.AgentId)" } else { $null }
        if (-not $Key) { continue }
        if (-not $AlertsByDevice.ContainsKey($Key)) { $AlertsByDevice[$Key] = [System.Collections.Generic.List[object]]::new() }
        $AlertsByDevice[$Key].Add($Alert)
    }

    $IntelYear = @{ 1 = 2010; 2 = 2011; 3 = 2012; 4 = 2013; 5 = 2015; 6 = 2015; 7 = 2017; 8 = 2018; 9 = 2019; 10 = 2020; 11 = 2021; 12 = 2022; 13 = 2023; 14 = 2024 }
    $AmdYear = @{ 1 = 2017; 2 = 2018; 3 = 2019; 4 = 2020; 5 = 2021; 6 = 2022; 7 = 2023; 8 = 2024; 9 = 2024 }

    foreach ($Agent in $Agents) {
        $Os = "$($Agent.OS)"
        $Parts = & $SplitBuild $Agent.OSBuild
        $Build = $Parts[0]; $Revision = $Parts[1]
        $IsServer = $Os -match 'Server' -or "$($Agent.OSType)" -match 'Server|Domain Controller'
        $IsWinOs = $Os -match 'Windows'

        # Windows version and support
        $Edition = if ($IsServer) { 'server' } elseif ($Os -match 'IoT' -and $Os -match 'LTS[BC]') { 'iotLtsc' } elseif ($Os -match 'LTS[BC]') { 'ltsc' } elseif ($Os -match 'Enterprise|Education') { 'enterprise' } else { 'homePro' }
        $Entry = if ($Build) { $Builds | Where-Object { [int]$_.build -eq $Build } | Select-Object -First 1 }
        $Ends = if ($Entry) { "$($Entry.$Edition)" } else { '' }
        $Support = 'Unknown'
        if ($IsWinOs -and $Build) {
            if ($Ends) {
                $EndDate = & $ToDate $Ends
                $Support = if ($EndDate -le $Now) { 'Unsupported' } elseif (($EndDate - $Now).TotalDays -le 90) { 'Ending soon' } else { 'Supported' }
            } elseif ($Entry) {
                # Listed build without an end date for this edition: that edition never had this build.
                $Support = 'Unknown'
            } elseif ($Build -gt $NewestKnownBuild) {
                $Support = 'Supported'
            }
        } elseif ($Os -match 'Windows (XP|Vista|7|8)\b|Server (2003|2008|2012)') {
            # Atera reports some old systems without a build number; their support ended long ago.
            $Support = 'Unsupported'
        } elseif ($Os -match 'Windows 10' -and $Os -notmatch 'LTS[BC]|Server' -and $Now -ge [datetime]'2025-10-14') {
            # Every non-LTSC Windows 10 version reached end of support on 14 Oct 2025 (22H2 last).
            $Support = 'Unsupported'
        }
        $VersionName = if ($Entry) {
            $Names = @("$($Entry.name)" -split ' / ')
            if ($IsServer) { "Windows $($Names[-1] -replace '^Windows ', '')" } else { $Names[0] }
        } elseif ($IsWinOs -and $Build) {
            $Family = if ($IsServer) { 'Windows Server' } elseif ($Build -ge 22000) { 'Windows 11' } else { 'Windows 10' }
            "$Family $($Agent.OSVersion)".Trim()
        } else { ($Os -replace '^Microsoft\s+', '' -replace '\s+x(64|86)$', '' -replace '\s+', ' ').Trim() }
        if ($Edition -in @('ltsc', 'iotLtsc')) { $VersionName = "$VersionName LTSC" }

        # Updates
        $Family = if ($Build) { & $FamilyOf $Build } else { $null }
        $Latest = if ($Family -and $Reference.ContainsKey($Family)) { $Reference[$Family] } else { $null }
        # Within 50 revisions of the reference counts as the same month's patch level: out-of-band fixes and
        # optional previews are small steps (tens of revisions); a missed month is a bigger jump.
        $UpdateStatus = if ($null -eq $Latest -or $null -eq $Revision) { 'Unknown' } elseif ($Revision -ge ($Latest - 50)) { 'Up to date' } else { 'Behind' }

        # Hardware
        $MemoryGB = if ($Agent.Memory) { [int][math]::Round([double]$Agent.Memory / 1024) } else { $null }
        $Cores = if ($Agent.ProcessorCoresCount) { [int]$Agent.ProcessorCoresCount } else { $null }
        $Cpu = ("$($Agent.Processor)" -replace '\((R|TM|tm|r)\)', '' -replace '\s+', ' ').Trim()
        $CpuSummary = $Cpu; $CpuYear = $null; $Win11 = 'Unknown'; $Entry_Level = $false; $Very_Old = $false
        if ($Cpu -match 'Core Ultra (X?\d)') {
            $CpuSummary = "Intel Core Ultra $($Matches[1])"; $CpuYear = 2024; $Win11 = 'Yes'
        } elseif ($Cpu -match 'Core ([3579]) (\d)\d{2}[A-Z]') {
            # Intel Core 3/5/7 (Series 1 and later, 2023+): 'Core 7 150U'
            $CpuSummary = "Intel Core $($Matches[1])"; $CpuYear = 2023; $Win11 = 'Yes'
            if ($Matches[1] -eq '3') { $Entry_Level = $true }
        } elseif ($Cpu -match 'Core (i[3579]) CPU [A-Z]? ?(\d{3})\b') {
            # 1st generation (2010): 'Core i7 CPU L 640', 'Core i3 CPU M 380', 'Core i7 CPU 860'
            $CpuSummary = "Intel Core $($Matches[1]), 1st gen"; $CpuYear = 2010; $Win11 = 'No'
            if ($Matches[1] -eq 'i3') { $Entry_Level = $true }
        } elseif ($Cpu -match 'Core (i[3579])[- ](\d{3,5})([A-Z]\w*)?') {
            $Family = $Matches[1]; $Model = $Matches[2]; $Suffix = "$($Matches[3])"
            $Gen = if ($Model.Length -eq 5) { [int]$Model.Substring(0, 2) } elseif ($Model.Length -eq 4 -and $Suffix -match '^G\d' -and $Model -match '^1[01]') { [int]$Model.Substring(0, 2) } elseif ($Model.Length -eq 4) { [int]$Model.Substring(0, 1) } else { 1 }
            if ($Cpu -match '(\d{1,2})th Gen') { $Gen = [int]$Matches[1] }
            $CpuYear = $IntelYear[$Gen]
            $Win11 = if ($Gen -ge 8) { 'Yes' } else { 'No' }
            $CpuSummary = "Intel Core $Family, $Gen$(switch ($Gen) { 1 { 'st' } 2 { 'nd' } 3 { 'rd' } default { 'th' } }) gen"
            if ($Family -eq 'i3') { $Entry_Level = $true }
        } elseif ($Cpu -match 'Ryzen (\d)( PRO)? (\d)(\d{3})([A-Z]*)') {
            $Tier = [int]$Matches[1]; $Series = [int]$Matches[3]; $AmdSuffix = "$($Matches[5])"
            $CpuYear = $AmdYear[$Series]
            # Ryzen 1000 and the 2000-series APUs (2200G/2400G, 2x00U/H - first-generation Zen) are not on
            # Microsoft's Windows 11 list; 2000-series desktop CPUs (Zen+) and later are.
            $Win11 = if ($Series -ge 3 -or ($Series -eq 2 -and $AmdSuffix -notmatch '^(G|GE|U|H|HS)$')) { 'Yes' } else { 'No' }
            $CpuSummary = "AMD Ryzen $Tier $($Series)000 series"
            if ($Tier -le 3) { $Entry_Level = $true }
        } elseif ($Cpu -match 'Xeon.*\bE[357]-\d{4}\w?\s*v(\d)') {
            $CpuYear = @{ 1 = 2011; 2 = 2012; 3 = 2013; 4 = 2015; 5 = 2015; 6 = 2017 }[[int]$Matches[1]]
            $CpuSummary = "Intel Xeon (v$($Matches[1]))"; $Win11 = 'No'
        } elseif ($Cpu -match 'Xeon.*\bE\d{4,5}\b') {
            $CpuSummary = 'Intel Xeon'; $CpuYear = 2010; $Win11 = 'No'
        } elseif ($Cpu -match 'AMD FX') {
            $CpuSummary = 'AMD FX'; $CpuYear = 2012; $Win11 = 'No'
        } elseif ($Cpu -match 'Celeron|Pentium|Atom|Athlon|AMD A\d|Core2|Core 2') {
            $CpuSummary = "$(($Cpu -split ' CPU| @')[0])"; $Entry_Level = $true; $Very_Old = $Cpu -match 'Core ?2|Atom'
            if ($Very_Old) { $Win11 = 'No' }
        }
        if ($CpuYear) { $CpuSummary = "$CpuSummary (c. $CpuYear)" }

        $Weak = [System.Collections.Generic.List[string]]::new()
        $Limited = [System.Collections.Generic.List[string]]::new()
        if ($null -ne $MemoryGB) {
            if ($MemoryGB -le 4) { $Weak.Add("$MemoryGB GB RAM") } elseif ($MemoryGB -le 8) { $Limited.Add("$MemoryGB GB RAM") }
        }
        if ($null -ne $Cores -and $Cores -le 2) { $Weak.Add("$Cores-core CPU") }
        if ($Very_Old) { $Weak.Add('very old CPU') }
        elseif ($Entry_Level) { $Limited.Add('entry-level CPU') }
        if (-not $IsServer -and $Win11 -eq 'No') { $Weak.Add('CPU too old for Windows 11') }
        if ($CpuYear) {
            $Age = $Now.Year - $CpuYear
            if ($Age -ge 10) { $Weak.Add("CPU about $Age years old") } elseif ($Age -ge 7) { $Limited.Add("CPU about $Age years old") }
        }
        # One hard limit, or two lesser ones together (e.g. 8 GB RAM on an 8-year-old CPU), makes it weak.
        $HardwareTier = if ($Weak.Count -gt 0 -or $Limited.Count -ge 2) { 'Weak' } elseif ($Limited.Count -gt 0) { 'Limited' } else { 'Good' }
        $HardwareNotes = (@($Weak) + @($Limited)) -join '; '
        if ($Os -match 'IoT') {
            # IoT editions run machines and kiosks, sized for one job: not rated like office computers.
            $HardwareTier = 'Special purpose'; $HardwareNotes = ''
        }

        # Disk (system drive, sizes in MB)
        $SystemDrive = if ($Agent.SystemDrive) { "$($Agent.SystemDrive)".TrimEnd('\') } else { 'C:' }
        $Disk = @($Agent.HardwareDisks) | Where-Object { $_ -and "$($_.Drive)".TrimEnd('\') -ieq $SystemDrive } | Select-Object -First 1
        $FreePct = $null; $FreeGB = $null
        if ($Disk -and [double]$Disk.Total -gt 0) {
            $FreePct = [int][math]::Round(100 * [double]$Disk.Free / [double]$Disk.Total)
            $FreeGB = [int][math]::Round([double]$Disk.Free / 1024)
        }

        $Seen = & $ToDate $Agent.LastSeen
        $Reboot = & $ToDate $Agent.LastRebootTime
        $DaysSeen = if ($Seen) { [int][math]::Floor(($Now - $Seen).TotalDays) } else { $null }
        # Uptime when last seen: an offline device has not been running since, so 'now' would overstate it.
        $DaysReboot = if ($Reboot) { [int][math]::Floor(($(if ($Seen) { $Seen } else { $Now }) - $Reboot).TotalDays) } else { $null }

        # Alerts
        $DeviceAlerts = @()
        if ($Agent.DeviceGuid -and $AlertsByDevice.ContainsKey("g:$($Agent.DeviceGuid)")) { $DeviceAlerts = @($AlertsByDevice["g:$($Agent.DeviceGuid)"]) }
        elseif ($AlertsByDevice.ContainsKey("a:$($Agent.AgentID)")) { $DeviceAlerts = @($AlertsByDevice["a:$($Agent.AgentID)"]) }
        $DayOf = { param($A) $d = & $ToDate $A.Created; if ($d) { $d.ToString('yyyy-MM-dd') } }
        $ResourceDays = @($DeviceAlerts | Where-Object { "$($_.Title)" -match 'CPU|Memory|RAM' } | ForEach-Object { & $DayOf $_ } | Where-Object { $_ } | Sort-Object -Unique).Count
        $DiskDays = @($DeviceAlerts | Where-Object { "$($_.Title)" -match 'Disk' } | ForEach-Object { & $DayOf $_ } | Where-Object { $_ } | Sort-Object -Unique).Count

        # Overall health
        $Attention = [System.Collections.Generic.List[string]]::new()
        $Check = [System.Collections.Generic.List[string]]::new()
        if ($Support -eq 'Unsupported') { $Attention.Add("$VersionName no longer gets security updates") }
        elseif ($Support -eq 'Ending soon') { $Check.Add("$VersionName security updates end $Ends") }
        if ($UpdateStatus -eq 'Behind') { $Attention.Add('behind on Windows updates') }
        if ($null -ne $DaysSeen -and $DaysSeen -gt 30) { $Attention.Add("not seen for $DaysSeen days") }
        elseif ($null -ne $DaysSeen -and $DaysSeen -gt 7) { $Check.Add("not seen for $DaysSeen days") }
        if ($null -ne $DaysReboot -and $DaysReboot -gt 30 -and ($null -eq $DaysSeen -or $DaysSeen -le 30)) {
            $Attention.Add($(if ($null -ne $DaysSeen -and $DaysSeen -gt 7) { "had not restarted for $DaysReboot days when last seen" } else { "not restarted for $DaysReboot days" }))
        }
        if ($null -ne $FreePct -and $FreePct -lt 10) { $Attention.Add("$SystemDrive only $FreePct% free") } elseif ($null -ne $FreePct -and $FreePct -lt 20) { $Check.Add("$SystemDrive $FreePct% free") }
        if ($ResourceDays -ge 5) { $Attention.Add("CPU or memory alerts on $ResourceDays days") } elseif ($ResourceDays -ge 2) { $Check.Add("CPU or memory alerts on $ResourceDays days") }
        if ($HardwareTier -eq 'Weak') { $Attention.Add("weak hardware ($HardwareNotes)") } elseif ($HardwareTier -eq 'Limited') { $Check.Add("limited hardware ($HardwareNotes)") }
        $IsHome = $Os -match '\bHome\b'
        if ($IsHome) { $Check.Add('Windows Home edition') }
        $Health = if ($Attention.Count -gt 0) { 'Needs attention' } elseif ($Check.Count -gt 0) { 'Check' } else { 'Good' }

        $Out = [ordered]@{}
        foreach ($Property in $Agent.PSObject.Properties) { $Out[$Property.Name] = $Property.Value }
        $Out.WindowsVersion = $VersionName
        $Out.WindowsSupport = $Support
        $Out.WindowsSupportEnds = $Ends
        $Out.IsHomeEdition = [bool]$IsHome
        $Out.UpdateStatus = $UpdateStatus
        $Out.LatestBuild = $(if ($null -ne $Latest) { "$Build.$Latest" } else { '' })
        $Out.MemoryGB = $MemoryGB
        $Out.CpuSummary = $CpuSummary
        $Out.CpuYear = $CpuYear
        $Out.Windows11Ready = $Win11
        $Out.HardwareTier = $HardwareTier
        $Out.HardwareNotes = $HardwareNotes
        $Out.SystemDiskFreePercent = $FreePct
        $Out.SystemDiskFreeGB = $FreeGB
        $Out.DaysSinceSeen = $DaysSeen
        $Out.DaysSinceReboot = $DaysReboot
        $Out.AlertCount = $DeviceAlerts.Count
        $Out.ResourceAlertDays = $ResourceDays
        $Out.DiskAlertDays = $DiskDays
        $Out.HealthStatus = $Health
        $Out.HealthNotes = (@($Attention) + @($Check)) -join '; '
        [pscustomobject]$Out
    }
}
