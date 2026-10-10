# Pester tests for Get-AteraDeviceInsight: the plain-English verdicts the Atera sync adds to devices.
#
# Pins: update status against the fleet's common newest revision (a lone preview build does not
# mark others behind); Windows support by build and edition, from Config/WindowsLifecycle.json;
# CPU parsing and hardware tiers; disk, restart and last-seen ages; recurring resource alerts;
# and the overall health verdict with its reasons.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    foreach ($Name in 'Get-AteraDeviceInsight', 'Get-AteraMemoryPressure', 'ConvertTo-AteraPatchSummary', 'ConvertTo-AteraLocalTime', 'Get-AteraDeviceRating', 'ConvertTo-AteraCpuInfo', 'Resolve-AteraDeviceRules') {
        . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter "$Name.ps1" | Select-Object -First 1 -ExpandProperty FullName)
    }
    $script:Now = [datetime]::new(2026, 10, 9, 12, 0, 0, [DateTimeKind]::Utc)
    $script:Lifecycle = Get-Content (Join-Path $RepoRoot 'Config/WindowsLifecycle.json') -Raw | ConvertFrom-Json

    function New-Agent {
        param([string]$Name, [string]$OS = 'Microsoft Windows 11 Pro  x64', [string]$Build = '26200.9457', [string]$Cpu = '12th Gen Intel(R) Core(TM) i5-12400', [int]$Cores = 6, [int]$MemoryMB = 16384,
            [string]$Seen = '2026-10-09T10:00:00Z', [string]$Reboot = '2026-10-01T08:00:00Z', [double]$FreeMB = 400000, [double]$TotalMB = 500000)
        [pscustomobject]@{ AgentID = [math]::Abs($Name.GetHashCode()); DeviceGuid = "guid-$Name"; MachineName = $Name; OS = $OS; OSBuild = $Build; OSType = 'Work Station'; Processor = $Cpu; ProcessorCoresCount = $Cores; Memory = $MemoryMB
            LastSeen = $Seen; LastRebootTime = $Reboot; SystemDrive = 'C:'; HardwareDisks = @([pscustomobject]@{ Drive = 'C:'; Free = $FreeMB; Total = $TotalMB }) }
    }
    function Get-Insight([object[]]$Agents, [object[]]$Alerts = @(), $Rules) {
        @(Get-AteraDeviceInsight -Agents $Agents -Alerts $Alerts -Now $script:Now -Lifecycle $script:Lifecycle -Rules $Rules)
    }
}

Describe 'Get-AteraDeviceInsight' {
    It 'pools builds that share monthly updates and ignores an early preview and small out-of-band steps' {
        $Fleet = @(
            New-Agent 'P1' -Build '26200.9457'; New-Agent 'P2' -Build '26200.9457'; New-Agent 'P3' -Build '26200.9457'
            New-Agent 'PREVIEW1' -Build '26300.9550'; New-Agent 'PREVIEW2' -Build '26300.9550'
            New-Agent 'ON26300' -Build '26300.9457'
            New-Agent 'PATCHDAY' -Build '26100.9445'
            New-Agent 'MONTHSOLD' -Build '26200.8457'
        )
        $R = Get-Insight $Fleet
        ($R | Where-Object MachineName -EQ 'ON26300').UpdateStatus | Should -Be 'Up to date'
        ($R | Where-Object MachineName -EQ 'PATCHDAY').UpdateStatus | Should -Be 'Up to date'
        ($R | Where-Object MachineName -EQ 'MONTHSOLD').UpdateStatus | Should -Be 'Behind'
        ($R | Where-Object MachineName -EQ 'MONTHSOLD').LatestBuild | Should -Be '26200.9457'
    }

    It 'marks devices behind the newest common revision, ignoring a lone newer build' {
        $Fleet = @(
            New-Agent 'A' -Build '26200.9457'; New-Agent 'B' -Build '26200.9457'; New-Agent 'C' -Build '26200.9457'
            New-Agent 'OLD' -Build '26200.8457'
            New-Agent 'PREVIEW' -Build '26200.9600'
        )
        $R = Get-Insight $Fleet
        ($R | Where-Object MachineName -EQ 'A').UpdateStatus | Should -Be 'Up to date'
        ($R | Where-Object MachineName -EQ 'PREVIEW').UpdateStatus | Should -Be 'Up to date'
        ($R | Where-Object MachineName -EQ 'OLD').UpdateStatus | Should -Be 'Behind'
        ($R | Where-Object MachineName -EQ 'OLD').LatestBuild | Should -Be '26200.9457'
    }

    It 'says Unknown when too few recently seen devices share the build' {
        $R = Get-Insight @(New-Agent 'ONLY' -Build '22631.5000')
        $R[0].UpdateStatus | Should -Be 'Unknown'
    }

    It 'works out Windows support for <Case>' -ForEach @(
        @{ Case = 'Windows 10 22H2'; OS = 'Microsoft Windows 10 Pro x64'; Build = '19045.6466'; Support = 'Unsupported'; Version = 'Windows 10 22H2' }
        @{ Case = 'Windows 11 24H2 Pro (ends 13 Oct 2026)'; OS = 'Microsoft Windows 11 Pro x64'; Build = '26100.6000'; Support = 'Ending soon'; Version = 'Windows 11 24H2' }
        @{ Case = 'Windows 11 24H2 Enterprise'; OS = 'Microsoft Windows 11 Enterprise x64'; Build = '26100.6000'; Support = 'Supported'; Version = 'Windows 11 24H2' }
        @{ Case = 'Windows 11 IoT LTSC 2024'; OS = 'Microsoft Windows 11 IoT Enterprise LTSC x64'; Build = '26100.6000'; Support = 'Supported'; Version = 'Windows 11 24H2 LTSC' }
        @{ Case = 'Windows 11 25H2'; OS = 'Microsoft Windows 11 Pro x64'; Build = '26200.9457'; Support = 'Supported'; Version = 'Windows 11 25H2' }
        @{ Case = 'Windows 11 26H2'; OS = 'Microsoft Windows 11 Pro x64'; Build = '26300.9550'; Support = 'Supported'; Version = 'Windows 11 26H2' }
        @{ Case = 'a build newer than the table'; OS = 'Microsoft Windows 11 Pro x64'; Build = '28000.1000'; Support = 'Supported'; Version = 'Windows 11' }
        @{ Case = 'Server 2019'; OS = 'Microsoft Windows Server 2019 Standard'; Build = '17763.7000'; Support = 'Supported'; Version = 'Windows Server 2019' }
        @{ Case = 'Server 2012 R2'; OS = 'Microsoft Windows Server 2012 R2 Essentials x64'; Build = '9600.22000'; Support = 'Unsupported'; Version = 'Windows Server 2012 R2' }
        @{ Case = 'Windows 7 without a build'; OS = 'Microsoft Windows 7 Professional SP1'; Build = ''; Support = 'Unsupported'; Version = 'Windows 7 Professional SP1' }
        @{ Case = 'Windows 10 without a build'; OS = 'Microsoft Windows 10 Pro x64'; Build = ''; Support = 'Unsupported'; Version = 'Windows 10 Pro' }
    ) {
        $R = Get-Insight @(New-Agent 'X' -OS $OS -Build $Build)
        $R[0].WindowsSupport | Should -Be $Support
        $R[0].WindowsVersion | Should -Be $Version
    }

    It 'reads <Cpu> as <Summary>, Windows 11 ready: <Ready>' -ForEach @(
        @{ Cpu = 'Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz'; Summary = 'Intel Core i5, 8th gen (c. 2018)'; Ready = 'Yes' }
        @{ Cpu = 'Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz'; Summary = 'Intel Core i7, 6th gen (c. 2015)'; Ready = 'No' }
        @{ Cpu = 'Intel(R) Core(TM) i7-1065G7 CPU @ 1.30GHz'; Summary = 'Intel Core i7, 10th gen (c. 2020)'; Ready = 'Yes' }
        @{ Cpu = '12th Gen Intel(R) Core(TM) i5-12400'; Summary = 'Intel Core i5, 12th gen (c. 2022)'; Ready = 'Yes' }
        @{ Cpu = 'Intel(R) Core(TM) i3 CPU M 380 @ 2.53GHz'; Summary = 'Intel Core i3, 1st gen (c. 2010)'; Ready = 'No' }
        @{ Cpu = 'AMD Ryzen 3 3200G with Radeon Vega Graphics'; Summary = 'AMD Ryzen 3 3000 series (c. 2019)'; Ready = 'Yes' }
        @{ Cpu = 'AMD Ryzen 5 1600 Six-Core Processor'; Summary = 'AMD Ryzen 5 1000 series (c. 2017)'; Ready = 'No' }
        @{ Cpu = 'AMD Ryzen 5 2400G with Radeon Vega Graphics'; Summary = 'AMD Ryzen 5 2000 series (c. 2018)'; Ready = 'No' }
        @{ Cpu = 'AMD Ryzen 7 2700X Eight-Core Processor'; Summary = 'AMD Ryzen 7 2000 series (c. 2018)'; Ready = 'Yes' }
        @{ Cpu = 'Intel(R) Xeon(R) CPU E3-1225 v5 @ 3.30GHz'; Summary = 'Intel Xeon (v5) (c. 2015)'; Ready = 'No' }
        @{ Cpu = 'Intel(R) Core(TM) Ultra 7 155H'; Summary = 'Intel Core Ultra 7 (c. 2024)'; Ready = 'Yes' }
    ) {
        $R = Get-Insight @(New-Agent 'X' -Cpu $Cpu)
        $R[0].CpuSummary | Should -Be $Summary
        $R[0].Windows11Ready | Should -Be $Ready
    }

    It 'rates hardware with the default device rules: <Case>' -ForEach @(
        @{ Case = '12th gen i7, 12 cores, 32 GB is good'; Cpu = '12th Gen Intel(R) Core(TM) i7-12700'; Cores = 12; MB = 32509; Rating = 'Good'; Why = '' }
        @{ Case = '10th gen i5, 6 cores, 16 GB is good'; Cpu = 'Intel(R) Core(TM) i5-10400F CPU @ 2.90GHz'; Cores = 6; MB = 16236; Rating = 'Good'; Why = '' }
        @{ Case = 'Ryzen 5 5600G, 15 GB is good'; Cpu = 'AMD Ryzen 5 5600G with Radeon Graphics'; Cores = 6; MB = 15669; Rating = 'Good'; Why = '' }
        @{ Case = '8th gen i3, 4 cores, 8 GB is check'; Cpu = 'Intel(R) Core(TM) i3-8100T CPU @ 3.10GHz'; Cores = 4; MB = 8024; Rating = 'Check'; Why = '8th gen Intel processor; 4-core processor; 8 GB memory' }
        @{ Case = '9th gen i5 is check'; Cpu = 'Intel(R) Core(TM) i5-9600K CPU @ 3.70GHz'; Cores = 6; MB = 16247; Rating = 'Check'; Why = '9th gen Intel processor' }
        @{ Case = 'Ryzen 3000 series is check'; Cpu = 'AMD Ryzen 3 3200G with Radeon Vega Graphics'; Cores = 4; MB = 14254; Rating = 'Check'; Why = 'Ryzen 3000 series processor; 4-core processor' }
        @{ Case = '10th gen with 4 cores and 8 GB is check'; Cpu = 'Intel(R) Core(TM) i5-10300H CPU @ 2.50GHz'; Cores = 4; MB = 8023; Rating = 'Check'; Why = '4-core processor; 8 GB memory' }
        @{ Case = '7th gen is needs attention'; Cpu = 'Intel(R) Core(TM) i7-7700 CPU @ 3.60GHz'; Cores = 4; MB = 16384; Rating = 'Needs attention'; Why = '7th gen Intel processor; processor cannot run Windows 11; 4-core processor' }
        @{ Case = 'Ryzen 2000 is needs attention'; Cpu = 'AMD Ryzen 5 2600 Six-Core Processor'; Cores = 6; MB = 16384; Rating = 'Needs attention'; Why = 'Ryzen 2000 series processor' }
        @{ Case = 'two cores is needs attention'; Cpu = '12th Gen Intel(R) Core(TM) i3-1215U'; Cores = 2; MB = 16384; Rating = 'Needs attention'; Why = '2-core processor' }
        @{ Case = 'under 8 GB is needs attention'; Cpu = '12th Gen Intel(R) Core(TM) i5-12400'; Cores = 6; MB = 6144; Rating = 'Needs attention'; Why = '6 GB memory' }
        @{ Case = 'Core Ultra is good'; Cpu = 'Intel(R) Core(TM) Ultra 5 125U'; Cores = 12; MB = 16384; Rating = 'Good'; Why = '' }
    ) {
        $R = Get-Insight @(New-Agent 'X' -Cpu $Cpu -Cores $Cores -MemoryMB $MB)
        $R[0].HardwareRating | Should -Be $Rating
        $R[0].HardwareNotes | Should -Be $Why
    }

    It 'rates the same hardware differently when the rules change' {
        $Agent = New-Agent 'OLDER' -Cpu 'Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz' -Cores 6 -MemoryMB 8059
        (Get-Insight @($Agent))[0].HardwareRating | Should -Be 'Check'
        $Strict = @(@{ id = 'intelGeneration'; check = 10; attention = 9 }, @{ id = 'memoryGB'; check = 16; attention = 16 })
        $R = Get-Insight @($Agent) -Rules $Strict
        $R[0].HardwareRating | Should -Be 'Needs attention'
        $R[0].HardwareNotes | Should -Be '8th gen Intel processor; 8 GB memory'
        $Relaxed = @(@{ id = 'intelGeneration'; check = $null; attention = 6 }, @{ id = 'memoryGB'; check = $null; attention = 4 })
        (Get-Insight @($Agent) -Rules $Relaxed)[0].HardwareRating | Should -Be 'Good'
    }

    It 'rates IoT and LTSC machines like any other computer' {
        $R = Get-Insight @(New-Agent 'KIOSK' -OS 'Microsoft Windows 11 IoT Enterprise LTSC x64' -Build '26100.9445' -Cpu 'Intel(R) Core(TM) i3-8100T CPU @ 3.10GHz' -Cores 4 -MemoryMB 8192)
        $R[0].HardwareRating | Should -Be 'Check'
    }

    It 'turns a rule off with a blank threshold or severity off' {
        $Agent = New-Agent 'HOME' -OS 'Microsoft Windows 11 Home x64'
        (Get-Insight @($Agent))[0].HealthStatus | Should -Be 'Check'
        (Get-Insight @($Agent) -Rules @(@{ id = 'windowsHome'; severity = 'off' }))[0].HealthStatus | Should -Be 'Good'
        (Get-Insight @($Agent) -Rules @(@{ id = 'windowsHome'; severity = 'attention' }))[0].HealthStatus | Should -Be 'Needs attention'
    }

    It 'counts memory over 90% only on weekdays in working hours (UK time), with the peak and main process' {
        $Agent = New-Agent 'BUSY'
        $Msg = { param($p) "The Memory Usage $p% is greater than the threshold of 90.00% for 9.00 minutes.`nTop 3 processes triggering the alert: chrome: 5,158.34 MB, svchost: 1,522.61 MB and Spotify: 1,152.19 MB" }
        $Alerts = @(
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = '2026-09-01T09:00:00Z'; AlertMessage = (& $Msg '95.90') }   # Tue 10:00 BST
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = '2026-09-01T13:00:00Z'; AlertMessage = (& $Msg '92.10') }   # same day
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = '2026-09-02T09:00:00Z'; AlertMessage = (& $Msg '97.00') }   # Wed
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = '2026-09-02T17:30:00Z'; AlertMessage = (& $Msg '99.00') }   # 18:30 BST - after hours
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = '2026-09-05T10:00:00Z'; AlertMessage = (& $Msg '99.00') }   # Saturday
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = '2026-09-03T10:00:00Z'; AlertMessage = (& $Msg '88.00') }   # under 90%
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'CPU Load'; Created = '2026-09-03T10:00:00Z'; AlertMessage = 'The CPU Load 100.00% is greater than the threshold' }
        )
        $R = Get-Insight @($Agent) $Alerts
        $R[0].MemoryHighDays | Should -Be 2
        $R[0].MemoryPeakPercent | Should -Be 97
        $R[0].MemoryTopProcess | Should -Be 'chrome'
        $R[0].HealthNotes | Should -Match 'memory over 90% in working hours on 2 days'
    }

    It 'flags drives over 75% full as Check by default, and as Needs attention above a set threshold' {
        $Agent = New-Agent 'DISKS'
        $Agent.HardwareDisks = @([pscustomobject]@{ Drive = 'C:'; Free = 100000; Total = 500000 }, [pscustomobject]@{ Drive = 'D:'; Free = 40000; Total = 1000000 }, [pscustomobject]@{ Drive = 'D:'; Free = 40000; Total = 1000000 }, [pscustomobject]@{ Drive = 'E:'; Free = 900000; Total = 1000000 }, [pscustomobject]@{ Drive = 'F:'; Free = 1; Total = 96 })
        $R = Get-Insight @($Agent)
        $R[0].DrivesOver75 | Should -Be 'C: 80%; D: 96%'
        $R[0].DrivesOver90 | Should -Be 'D: 96%'
        $R[0].FullestDrivePercent | Should -Be 96
        $R[0].HealthStatus | Should -Be 'Check'
        (Get-Insight @($Agent) -Rules @(@{ id = 'driveFull'; check = 75; attention = 90 }))[0].HealthStatus | Should -Be 'Needs attention'
        $R[0].HealthNotes | Should -Match 'D: 96% full'
        $R[0].HealthNotes | Should -Match 'C: 80% full'
    }

    It 'uses Atera''s patch scan for update status when there is one' {
        $Fleet = @(New-Agent 'A'; New-Agent 'B'; New-Agent 'WAITING'; New-Agent 'FAILING'; New-Agent 'OLDBUILD' -Build '26200.8457')
        $Patches = @{
            'guid-A'        = [pscustomobject]@{ PatchScanDate = '2026-10-09T10:00:00Z'; SecurityUpdatesWaiting = 0; OtherUpdatesWaiting = 1; UpdatesFailed = 0; LastSecurityUpdate = '2026-09-15'; UpdatesWaiting = 'Intel driver'; UpdatesFailing = '' }
            'guid-WAITING'  = [pscustomobject]@{ PatchScanDate = '2026-10-09T10:00:00Z'; SecurityUpdatesWaiting = 2; OtherUpdatesWaiting = 0; UpdatesFailed = 0; LastSecurityUpdate = '2026-06-09'; UpdatesWaiting = '2026-09 Security Update; .NET'; UpdatesFailing = '' }
            'guid-FAILING'  = [pscustomobject]@{ PatchScanDate = '2026-10-09T10:00:00Z'; SecurityUpdatesWaiting = 0; OtherUpdatesWaiting = 0; UpdatesFailed = 1; SecurityUpdatesFailed = 1; LastSecurityUpdate = '2026-09-15'; UpdatesWaiting = ''; UpdatesFailing = '2026-09 Security Update' }
            'guid-B'        = [pscustomobject]@{ PatchScanDate = '2026-10-09T10:00:00Z'; SecurityUpdatesWaiting = 0; OtherUpdatesWaiting = 0; UpdatesFailed = 0; SecurityUpdatesFailed = 0; DriversFailed = 1; LastSecurityUpdate = '2026-09-15'; UpdatesWaiting = ''; UpdatesFailing = ''; DriversFailing = 'Brother printer driver' }
            'guid-OLDBUILD' = [pscustomobject]@{ PatchScanDate = '2026-10-09T10:00:00Z'; SecurityUpdatesWaiting = 0; OtherUpdatesWaiting = 0; UpdatesFailed = 0; LastSecurityUpdate = '2026-09-15'; UpdatesWaiting = ''; UpdatesFailing = '' }
        }
        $R = @(Get-AteraDeviceInsight -Agents $Fleet -Now $script:Now -Lifecycle $script:Lifecycle -Patches $Patches)
        ($R | Where-Object MachineName -EQ 'A').UpdateStatus | Should -Be 'Up to date'
        ($R | Where-Object MachineName -EQ 'A').UpdateSource | Should -Be 'Atera patch scan'
        ($R | Where-Object MachineName -EQ 'WAITING').UpdateStatus | Should -Be 'Behind'
        ($R | Where-Object MachineName -EQ 'WAITING').HealthNotes | Should -Match '2 security updates waiting'
        ($R | Where-Object MachineName -EQ 'FAILING').UpdateStatus | Should -Be 'Failing'
        # the scan wins over the build comparison
        ($R | Where-Object MachineName -EQ 'OLDBUILD').UpdateStatus | Should -Be 'Up to date'
        # a failed driver is optional: listed, but the device stays up to date and healthy
        ($R | Where-Object MachineName -EQ 'B').UpdateStatus | Should -Be 'Up to date'
        ($R | Where-Object MachineName -EQ 'B').HealthStatus | Should -Be 'Good'
        ($R | Where-Object MachineName -EQ 'B').DriversFailing | Should -Be 'Brother printer driver'
    }

    It 'summarises a patch scan, ignoring antivirus definitions' {
        $Installed = [pscustomobject]@{ timestamp = '2026-10-09T12:45:06Z'; installedUpdates = @(
                [pscustomobject]@{ name = 'Old'; class = 'Security Updates'; installDate = '2026-08-12T00:00:00Z' }
                [pscustomobject]@{ name = 'Sept'; class = 'Security Updates'; installDate = '2026-09-15T00:00:00Z' }
                [pscustomobject]@{ name = 'Windows Malicious Software Removal Tool x64 - v5.130 (KB890830)'; class = 'Update Rollups'; installDate = '2026-09-24T00:00:00Z' }
                [pscustomobject]@{ name = 'Defender'; class = 'Definition Updates'; installDate = '2026-10-09T00:00:00Z' }) }
        $Available = [pscustomobject]@{ timestamp = '2026-10-09T12:45:06Z'; availableUpdates = @(
                [pscustomobject]@{ name = 'Brother - Printer - 3.3.0.0'; class = 'Hardware driver updates'; status = 'Failed' }
                [pscustomobject]@{ name = 'Security Intelligence Update for Microsoft Defender Antivirus'; class = 'Definition Updates'; status = 'Available' }
                [pscustomobject]@{ name = '2026-09 Security Update (KB5129195)'; class = 'Security Updates'; status = 'Available' }
                [pscustomobject]@{ name = 'Insyde firmware'; class = 'Hardware driver updates'; status = 'Available' }) }
        $S = ConvertTo-AteraPatchSummary -Installed $Installed -Available $Available
        $S.SecurityUpdatesWaiting | Should -Be 1
        $S.OtherUpdatesWaiting | Should -Be 0
        $S.DriverUpdatesWaiting | Should -Be 1
        $S.UpdatesFailed | Should -Be 0
        $S.DriversFailed | Should -Be 1
        $S.SecurityUpdatesFailed | Should -Be 0
        $S.DriversWaiting | Should -Be 'Insyde firmware'
        $S.LastSecurityUpdate | Should -Be '2026-09-15'
        $S.UpdatesWaiting | Should -Be '2026-09 Security Update (KB5129195)'
        $S.UpdatesFailing | Should -Be ''
        $S.DriversFailing | Should -Be 'Brother - Printer - 3.3.0.0'
        $S.PatchScanDate | Should -Be '2026-10-09T12:45:06Z'
    }

    It 'gives a healthy device Good, and lists every reason otherwise' {
        $Fleet = @(New-Agent 'A'; New-Agent 'B'; New-Agent 'LAPTOP' -OS 'Microsoft Windows 11 Home x64' -Build '26200.8457' -Seen '2026-09-24T15:00:00Z' -Reboot '2026-06-09T09:00:00Z' -FreeMB 20000 -TotalMB 500000)
        $R = Get-Insight $Fleet
        ($R | Where-Object MachineName -EQ 'A').HealthStatus | Should -Be 'Good'
        $L = $R | Where-Object MachineName -EQ 'LAPTOP'
        # Every one of these is a Check item under the default rules.
        $L.HealthStatus | Should -Be 'Check'
        $L.DaysSinceSeen | Should -Be 15
        $L.DaysSinceReboot | Should -Be 107
        $L.SystemDiskFreePercent | Should -Be 4
        $L.IsHomeEdition | Should -BeTrue
        $L.HealthNotes | Should -Match 'behind on Windows updates'
        $L.HealthNotes | Should -Match 'had not restarted for 107 days when last seen'
        $L.HealthNotes | Should -Match 'C: 96% full'
        $L.HealthNotes | Should -Match 'Windows Home edition'
    }
}
