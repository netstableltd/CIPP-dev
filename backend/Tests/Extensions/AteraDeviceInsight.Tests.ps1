# Pester tests for Get-AteraDeviceInsight: the plain-English verdicts the Atera sync adds to devices.
#
# Pins: update status against the fleet's common newest revision (a lone preview build does not
# mark others behind); Windows support by build and edition, from Config/WindowsLifecycle.json;
# CPU parsing and hardware tiers; disk, restart and last-seen ages; recurring resource alerts;
# and the overall health verdict with its reasons.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Get-AteraDeviceInsight.ps1' | Select-Object -First 1 -ExpandProperty FullName)
    $script:Now = [datetime]::new(2026, 10, 9, 12, 0, 0, [DateTimeKind]::Utc)
    $script:Lifecycle = Get-Content (Join-Path $RepoRoot 'Config/WindowsLifecycle.json') -Raw | ConvertFrom-Json

    function New-Agent {
        param([string]$Name, [string]$OS = 'Microsoft Windows 11 Pro  x64', [string]$Build = '26200.9457', [string]$Cpu = '12th Gen Intel(R) Core(TM) i5-12400', [int]$Cores = 6, [int]$MemoryMB = 16384,
            [string]$Seen = '2026-10-09T10:00:00Z', [string]$Reboot = '2026-10-01T08:00:00Z', [double]$FreeMB = 400000, [double]$TotalMB = 500000)
        [pscustomobject]@{ AgentID = [math]::Abs($Name.GetHashCode()); DeviceGuid = "guid-$Name"; MachineName = $Name; OS = $OS; OSBuild = $Build; OSType = 'Work Station'; Processor = $Cpu; ProcessorCoresCount = $Cores; Memory = $MemoryMB
            LastSeen = $Seen; LastRebootTime = $Reboot; SystemDrive = 'C:'; HardwareDisks = @([pscustomobject]@{ Drive = 'C:'; Free = $FreeMB; Total = $TotalMB }) }
    }
    function Get-Insight([object[]]$Agents, [object[]]$Alerts = @()) {
        @(Get-AteraDeviceInsight -Agents $Agents -Alerts $Alerts -Now $script:Now -Lifecycle $script:Lifecycle)
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

    It 'grades hardware: <Case>' -ForEach @(
        @{ Case = 'modern with 16 GB is good'; Cpu = '12th Gen Intel(R) Core(TM) i5-12400'; Cores = 6; MB = 16384; Tier = 'Good' }
        @{ Case = '8 GB alone is limited'; Cpu = '12th Gen Intel(R) Core(TM) i5-12400'; Cores = 6; MB = 8192; Tier = 'Limited' }
        @{ Case = '8 GB on an 8-year-old CPU is weak'; Cpu = 'Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz'; Cores = 6; MB = 8059; Tier = 'Weak' }
        @{ Case = '4 GB is weak'; Cpu = '12th Gen Intel(R) Core(TM) i5-12400'; Cores = 6; MB = 4096; Tier = 'Weak' }
        @{ Case = 'two cores is weak'; Cpu = 'Intel(R) Pentium(R) CPU N3540 @ 2.16GHz'; Cores = 2; MB = 8192; Tier = 'Weak' }
        @{ Case = 'a CPU too old for Windows 11 is weak'; Cpu = 'Intel(R) Core(TM) i7-6700 CPU @ 3.40GHz'; Cores = 4; MB = 16384; Tier = 'Weak' }
    ) {
        $R = Get-Insight @(New-Agent 'X' -Cpu $Cpu -Cores $Cores -MemoryMB $MB)
        $R[0].HardwareTier | Should -Be $Tier
    }

    It 'does not rate IoT machines like office computers' {
        $R = Get-Insight @(New-Agent 'KIOSK' -OS 'Microsoft Windows 11 IoT Enterprise LTSC x64' -Build '26100.9445' -Cpu 'Intel(R) Core(TM) i3-8100T CPU @ 3.10GHz' -Cores 4 -MemoryMB 8192)
        $R[0].HardwareTier | Should -Be 'Special purpose'
        $R[0].HealthNotes | Should -Not -Match 'hardware'
    }

    It 'counts days with CPU or memory alerts and flags a regularly overloaded device' {
        $Agent = New-Agent 'BUSY'
        $Alerts = @(foreach ($d in 1..6) { [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Memory Usage'; Created = "2026-09-0$($d)T10:00:00Z" } }
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'CPU Load'; Created = '2026-09-01T11:00:00Z' }
            [pscustomobject]@{ DeviceGuid = 'guid-BUSY'; Title = 'Disk Usage(C:)'; Created = '2026-09-02T11:00:00Z' }
            [pscustomobject]@{ DeviceGuid = 'guid-OTHER'; Title = 'Memory Usage'; Created = '2026-09-02T11:00:00Z' })
        $R = Get-Insight @($Agent) $Alerts
        $R[0].ResourceAlertDays | Should -Be 6
        $R[0].DiskAlertDays | Should -Be 1
        $R[0].AlertCount | Should -Be 8
        $R[0].HealthStatus | Should -Be 'Needs attention'
        $R[0].HealthNotes | Should -Match 'CPU or memory alerts on 6 days'
    }

    It 'gives a healthy device Good, and lists every reason otherwise' {
        $Fleet = @(New-Agent 'A'; New-Agent 'B'; New-Agent 'LAPTOP' -OS 'Microsoft Windows 11 Home x64' -Build '26200.8457' -Seen '2026-09-24T15:00:00Z' -Reboot '2026-06-09T09:00:00Z' -FreeMB 20000 -TotalMB 500000)
        $R = Get-Insight $Fleet
        ($R | Where-Object MachineName -EQ 'A').HealthStatus | Should -Be 'Good'
        $L = $R | Where-Object MachineName -EQ 'LAPTOP'
        $L.HealthStatus | Should -Be 'Needs attention'
        $L.DaysSinceSeen | Should -Be 14
        $L.DaysSinceReboot | Should -Be 107
        $L.SystemDiskFreePercent | Should -Be 4
        $L.IsHomeEdition | Should -BeTrue
        $L.HealthNotes | Should -Match 'behind on Windows updates'
        $L.HealthNotes | Should -Match 'had not restarted for 107 days when last seen'
        $L.HealthNotes | Should -Match 'C: only 4% free'
        $L.HealthNotes | Should -Match 'Windows Home edition'
    }
}
