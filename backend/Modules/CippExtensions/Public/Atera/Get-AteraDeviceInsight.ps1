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

        UpdateStatus      'Up to date' | 'Behind' | 'Failing' | 'Unknown'. When Atera's patch scan is passed in
                          (-Patches), from that: Behind = security updates waiting, Failing = updates failing to
                          install. Otherwise (or when a device has no scan), compares the Windows build revision
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
        UpdateSource      'Atera patch scan' | 'Build comparison' | ''.
        PatchScanDate, SecurityUpdatesWaiting, OtherUpdatesWaiting, UpdatesFailed, LastSecurityUpdate,
        UpdatesWaiting, DriversWaiting, UpdatesFailing, SecurityUpdatesFailed - from Atera's patch scan
        (ConvertTo-AteraPatchSummary). Failing = a non-driver update failed; driver updates are optional
        and never flag a device.
        MemoryGB, CpuSummary, CpuYear (approximate launch year), Windows11Ready ('Yes'|'No'|'Unknown')
        CpuGeneration     Intel Core generation (8 = 8th gen) or Ryzen series (3 = 3000 series), from ConvertTo-AteraCpuInfo.
        HardwareRating    'Good' | 'Check' | 'Needs attention' from the hardware device rules (Get-AteraDeviceRating);
                          HardwareNotes gives the reasons. HardwareTier is the same as 'Meets baseline' |
                          'Borderline' | 'Below baseline'.
        SystemDiskFreePercent, SystemDiskFreeGB
        Drives            Every fixed drive with its fullness, e.g. 'C: 82% full; D: 40% full'.
        FullestDrivePercent, DrivesOver75 ('C: 82%'), DrivesOver90.
        MemoryHighDays    Distinct working days (weekdays, working hours in -TimeZone) with a memory alert above the threshold,
                          with MemoryPeakPercent and MemoryTopProcess (Get-AteraMemoryPressure).
        DaysSinceSeen, DaysSinceReboot
        AlertCount, ResourceAlertDays (distinct days with CPU or memory alerts), DiskAlertDays - over the
                          alerts passed in (the sync passes 90 days).
        HealthStatus      'Good' | 'Check' | 'Needs attention', with HealthNotes giving the reasons: the worst of every
                          device rule (Reports > Device Rules; defaults in Config/DeviceRatingRules.json).

    .PARAMETER Rules
        Device rules (Get-CIPPReportDeviceRules). Defaults from Config/DeviceRatingRules.json when omitted.

    .PARAMETER Patches
        Optional hashtable of DeviceGuid -> output of ConvertTo-AteraPatchSummary.

    .PARAMETER TimeZone
        Time zone for "working hours" when reading memory alerts. Default Europe/London.

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
        $Lifecycle,
        [hashtable]$Patches = @{},
        [string]$TimeZone = 'Europe/London',
        $Rules
    )

    $RuleSet = Resolve-AteraDeviceRules -Rules $Rules
    $RuleValue = { param($Id, $Default) if ($RuleSet[$Id] -and $null -ne $RuleSet[$Id].value -and "$($RuleSet[$Id].value)" -ne '') { [int]$RuleSet[$Id].value } else { $Default } }

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

    $MemoryPressure = @{}
    foreach ($M in @(Get-AteraMemoryPressure -Alerts $Alerts -TimeZone $TimeZone -Threshold (& $RuleValue 'memoryThreshold' 90) -WorkdayStart (& $RuleValue 'workdayStart' 8) -WorkdayEnd (& $RuleValue 'workdayEnd' 18))) {
        $MemoryPressure[$(if ($M.DeviceGuid) { "g:$($M.DeviceGuid)" } else { "n:$($M.DeviceName)" })] = $M
    }

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
        $UpdateSource = if ($UpdateStatus -ne 'Unknown') { 'Build comparison' } else { '' }
        $Patch = if ($Agent.DeviceGuid -and $Patches.ContainsKey("$($Agent.DeviceGuid)")) { $Patches["$($Agent.DeviceGuid)"] } else { $null }
        if ($Patch -and $Patch.PatchScanDate) {
            # Atera's own patch scan is the better source: what the device actually still needs.
            $UpdateSource = 'Atera patch scan'
            $UpdateStatus = if ([int]$Patch.SecurityUpdatesWaiting -gt 0) { 'Behind' } elseif ([int]$Patch.UpdatesFailed -gt 0) { 'Failing' } else { 'Up to date' }
        }

        # Hardware
        $MemoryGB = ConvertTo-AteraMemoryGB -MemoryMB $Agent.Memory
        $Cores = if ($Agent.ProcessorCoresCount) { [int]$Agent.ProcessorCoresCount } else { $null }
        $CpuInfo = ConvertTo-AteraCpuInfo -Processor "$($Agent.Processor)"
        $CpuSummary = $CpuInfo.Summary; $CpuYear = $CpuInfo.Year; $Win11 = $CpuInfo.Win11

        # Disk (system drive, sizes in MB)
        $SystemDrive = if ($Agent.SystemDrive) { "$($Agent.SystemDrive)".TrimEnd('\') } else { 'C:' }
        $Disk = @($Agent.HardwareDisks) | Where-Object { $_ -and "$($_.Drive)".TrimEnd('\') -ieq $SystemDrive } | Select-Object -First 1
        $FreePct = $null; $FreeGB = $null
        if ($Disk -and [double]$Disk.Total -gt 0) {
            $FreePct = [int][math]::Round(100 * [double]$Disk.Free / [double]$Disk.Total)
            $FreeGB = [int][math]::Round([double]$Disk.Free / 1024)
        }

        # Every fixed drive's fullness.
        # Atera can list a drive more than once; tiny partitions (under 1 GB, e.g. recovery or EFI) are skipped.
        $DriveRows = @(@($Agent.HardwareDisks) | Where-Object { $_ -and [double]$_.Total -ge 1024 } | Group-Object { "$($_.Drive)".TrimEnd('\').ToUpperInvariant() } | ForEach-Object { $_.Group[0] } | ForEach-Object {
                [pscustomobject]@{ Drive = "$($_.Drive)".TrimEnd('\'); Percent = [int][math]::Round(100 * (1 - [double]$_.Free / [double]$_.Total)); FreeGB = [int][math]::Round([double]$_.Free / 1024); TotalGB = [int][math]::Round([double]$_.Total / 1024) }
            } | Sort-Object Drive)
        # DrivesOver75 lists drives over the 'Drive used' Check threshold (75% unless changed in the device rules).
        $DriveCheck = if ($RuleSet['driveFull'] -and "$($RuleSet['driveFull'].check)" -ne '') { [double]$RuleSet['driveFull'].check } else { 75 }
        $Over75 = @($DriveRows | Where-Object { $_.Percent -gt $DriveCheck })
        $Over90 = @($DriveRows | Where-Object { $_.Percent -gt 90 })

        $Seen = & $ToDate $Agent.LastSeen
        $Reboot = & $ToDate $Agent.LastRebootTime
        # Calendar days in the local time zone: seen on Friday and checked on Saturday is 1 day, not 0.
        $DaysSeen = if ($Seen) { [int]((ConvertTo-AteraLocalTime -Utc $Now -TimeZone $TimeZone).Date - (ConvertTo-AteraLocalTime -Utc $Seen -TimeZone $TimeZone).Date).TotalDays } else { $null }
        # Uptime when last seen: an offline device has not been running since, so 'now' would overstate it.
        $DaysReboot = if ($Reboot) { [int][math]::Floor(($(if ($Seen) { $Seen } else { $Now }) - $Reboot).TotalDays) } else { $null }

        # Alerts
        $DeviceAlerts = @()
        if ($Agent.DeviceGuid -and $AlertsByDevice.ContainsKey("g:$($Agent.DeviceGuid)")) { $DeviceAlerts = @($AlertsByDevice["g:$($Agent.DeviceGuid)"]) }
        elseif ($AlertsByDevice.ContainsKey("a:$($Agent.AgentID)")) { $DeviceAlerts = @($AlertsByDevice["a:$($Agent.AgentID)"]) }
        $DayOf = { param($A) $d = & $ToDate $A.Created; if ($d) { $d.ToString('yyyy-MM-dd') } }
        $ResourceDays = @($DeviceAlerts | Where-Object { "$($_.Title)" -match 'CPU|Memory|RAM' } | ForEach-Object { & $DayOf $_ } | Where-Object { $_ } | Sort-Object -Unique).Count
        $DiskDays = @($DeviceAlerts | Where-Object { "$($_.Title)" -match 'Disk' } | ForEach-Object { & $DayOf $_ } | Where-Object { $_ } | Sort-Object -Unique).Count

        $Mem = if ($Agent.DeviceGuid -and $MemoryPressure.ContainsKey("g:$($Agent.DeviceGuid)")) { $MemoryPressure["g:$($Agent.DeviceGuid)"] } elseif ($MemoryPressure.ContainsKey("n:$($Agent.MachineName)")) { $MemoryPressure["n:$($Agent.MachineName)"] } else { $null }
        $IsHome = $Os -match '\bHome\b'

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
        $Out.UpdateSource = $UpdateSource
        $Out.PatchScanDate = $(if ($Patch) { "$($Patch.PatchScanDate)" } else { '' })
        $Out.SecurityUpdatesWaiting = $(if ($Patch) { [int]$Patch.SecurityUpdatesWaiting } else { $null })
        $Out.OtherUpdatesWaiting = $(if ($Patch) { [int]$Patch.OtherUpdatesWaiting } else { $null })
        $Out.UpdatesFailed = $(if ($Patch) { [int]$Patch.UpdatesFailed } else { $null })
        $Out.LastSecurityUpdate = $(if ($Patch) { "$($Patch.LastSecurityUpdate)" } else { '' })
        $Out.UpdatesWaiting = $(if ($Patch) { "$($Patch.UpdatesWaiting)" } else { '' })
        $Out.DriversWaiting = $(if ($Patch) { "$($Patch.DriversWaiting)" } else { '' })
        $Out.DriversFailing = $(if ($Patch) { "$($Patch.DriversFailing)" } else { '' })
        $Out.SecurityUpdatesFailed = $(if ($Patch) { [int]$Patch.SecurityUpdatesFailed } else { $null })
        $Out.UpdatesFailing = $(if ($Patch) { "$($Patch.UpdatesFailing)" } else { '' })
        $Out.Drives = (@($DriveRows | ForEach-Object { "$($_.Drive) $($_.Percent)% full" }) -join '; ')
        $Out.FullestDrivePercent = $(if ($DriveRows.Count -gt 0) { [int](($DriveRows | Measure-Object Percent -Maximum).Maximum) } else { $null })
        $Out.DrivesOver75 = (@($Over75 | ForEach-Object { "$($_.Drive) $($_.Percent)%" }) -join '; ')
        $Out.DrivesOver90 = (@($Over90 | ForEach-Object { "$($_.Drive) $($_.Percent)%" }) -join '; ')
        $Out.MemoryHighDays = $(if ($Mem) { [int]$Mem.Days } else { 0 })
        $Out.MemoryPeakPercent = $(if ($Mem) { [int]$Mem.PeakPercent } else { $null })
        $Out.MemoryTopProcess = $(if ($Mem) { "$($Mem.TopProcess)" } else { '' })
        $Out.SystemDiskFreePercent = $FreePct
        $Out.SystemDiskFreeGB = $FreeGB
        $Out.DaysSinceSeen = $DaysSeen
        $Out.DaysSinceReboot = $DaysReboot
        $Out.AlertCount = $DeviceAlerts.Count
        $Out.ResourceAlertDays = $ResourceDays
        $Out.DiskAlertDays = $DiskDays
        # Ratings from the device rules (Reports > Device Rules).
        $Rating = Get-AteraDeviceRating -Device ([pscustomobject]$Out) -Rules $RuleSet
        $Out.CpuGeneration = $CpuInfo.Generation
        $Out.HardwareRating = $Rating.HardwareRating
        $Out.IsVirtual = $Rating.IsVirtual
        $Out.HardwareTier = $Rating.HardwareTier
        $Out.HardwareNotes = $Rating.HardwareNotes
        $Out.HealthStatus = $Rating.HealthStatus
        $Out.HealthNotes = $Rating.HealthNotes
        [pscustomobject]$Out
    }
}
