function Get-AteraDeviceRating {
    <#
    .SYNOPSIS
        Rates one computer as Good, Check or Needs attention using the device rules (Reports > Device Rules).

    .DESCRIPTION
        Works from the fields Get-AteraDeviceInsight adds to an Atera agent, so a report can re-rate devices
        with the current rules without waiting for the next sync. Two ratings come back:

        HardwareRating    from the hardware rules only (processor generation, cores, memory, Windows 11 support,
                          entry-level processors), with HardwareNotes giving the reasons.
        HealthStatus      the worst of the hardware rating and every other rule (Windows support, updates,
                          drives, memory alerts, last seen, restarts, Windows Home), with HealthNotes.

        Rules come from -Rules (Get-CIPPReportDeviceRules); anything missing falls back to the defaults in
        Config/DeviceRatingRules.json.

    .PARAMETER Device
        An agent with Get-AteraDeviceInsight's fields.

    .PARAMETER Rules
        Hashtable of rule id -> rule (check / attention / severity / value). Optional.

    .PARAMETER MemoryDays
        High-memory working days to rate on (a report passes its own period). Defaults to the device's
        MemoryHighDays.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Device,
        $Rules,
        [Nullable[int]]$MemoryDays
    )

    $R = Resolve-AteraDeviceRules -Rules $Rules
    $Get = { param($Name) if ($Device.PSObject.Properties.Name -contains $Name) { $Device.$Name } elseif ($Device -is [System.Collections.IDictionary] -and $Device.Contains($Name)) { $Device[$Name] } }
    $Num = { param($V) if ($null -eq $V -or "$V" -eq '') { $null } else { [double]$V } }

    # 'below' rules: attention when value < attention; check when value <= check.
    $Below = {
        param($Id, $Value)
        $Rule = $R[$Id]
        if (-not $Rule -or $null -eq $Value) { return $null }
        $A = & $Num $Rule.attention; $C = & $Num $Rule.check
        if ($null -ne $A -and $Value -lt $A) { return 'attention' }
        if ($null -ne $C -and $Value -le $C) { return 'check' }
        $null
    }
    # 'above' rules: attention when value > attention; check when value > check.
    $Above = {
        param($Id, $Value)
        $Rule = $R[$Id]
        if (-not $Rule -or $null -eq $Value) { return $null }
        $A = & $Num $Rule.attention; $C = & $Num $Rule.check
        if ($null -ne $A -and $Value -gt $A) { return 'attention' }
        if ($null -ne $C -and $Value -gt $C) { return 'check' }
        $null
    }
    $Flag = {
        param($Id)
        $Rule = $R[$Id]
        if ($Rule -and "$($Rule.severity)" -in @('attention', 'check')) { return "$($Rule.severity)" }
        $null
    }

    $HwAttention = [System.Collections.Generic.List[string]]::new()
    $HwCheck = [System.Collections.Generic.List[string]]::new()
    $Attention = [System.Collections.Generic.List[string]]::new()
    $Check = [System.Collections.Generic.List[string]]::new()
    $AddTo = {
        param($Level, $Note, [switch]$Hardware)
        if (-not $Level) { return }
        if ($Hardware) { if ($Level -eq 'attention') { $HwAttention.Add($Note) } else { $HwCheck.Add($Note) } }
        else { if ($Level -eq 'attention') { $Attention.Add($Note) } else { $Check.Add($Note) } }
    }

    # --- Hardware -------------------------------------------------------------------------------------
    $Os = "$(& $Get 'OS')"
    $IsServer = $Os -match 'Server' -or "$(& $Get 'OSType')" -match 'Server|Domain Controller'
    $Cpu = ConvertTo-AteraCpuInfo -Processor "$(& $Get 'Processor')"
    # Virtual machines get the processors and memory they are given, so hardware rules don't apply.
    $IsVirtual = "$(& $Get 'VendorBrandModel') $(& $Get 'Vendor')" -match '(?i)virtual machine|vmware|virtualbox|kvm|qemu|\bxen\b|hvm domu|parallels|hyper-v'
    if (-not $IsVirtual) {
        if ($Cpu.Vendor -eq 'Intel' -and $Cpu.Family -eq 'Core' -and $Cpu.Generation) {
            $Ord = "$($Cpu.Generation)$(switch ($Cpu.Generation) { 1 { 'st' } 2 { 'nd' } 3 { 'rd' } default { 'th' } })"
            & $AddTo (& $Below 'intelGeneration' $Cpu.Generation) "$Ord gen Intel processor" -Hardware
        } elseif ($Cpu.Family -eq 'Ryzen' -and $Cpu.Generation) {
            & $AddTo (& $Below 'ryzenSeries' $Cpu.Generation) "Ryzen $($Cpu.Generation)000 series processor" -Hardware
        }
        $Cores = & $Num (& $Get 'ProcessorCoresCount')
        & $AddTo (& $Below 'cores' $Cores) "$Cores-core processor" -Hardware
        # Memory fitted, from what Windows reports (shared graphics memory is not counted by Windows).
        $MemGB = if (& $Get 'Memory') { ConvertTo-AteraMemoryGB -MemoryMB (& $Get 'Memory') } else { & $Num (& $Get 'MemoryGB') }
        & $AddTo (& $Below 'memoryGB' $MemGB) "$MemGB GB memory" -Hardware
        $Win11 = if (& $Get 'Windows11Ready') { "$(& $Get 'Windows11Ready')" } else { $Cpu.Win11 }
        if (-not $IsServer -and $Win11 -eq 'No') { & $AddTo (& $Flag 'windows11') 'processor cannot run Windows 11' -Hardware }
        if ($Cpu.EntryLevel) { & $AddTo (& $Flag 'entryLevelCpu') 'entry-level processor' -Hardware }
    }
    $HardwareRating = if ($HwAttention.Count -gt 0) { 'Needs attention' } elseif ($HwCheck.Count -gt 0) { 'Check' } else { 'Good' }

    # --- Everything else -------------------------------------------------------------------------------
    $Version = "$(& $Get 'WindowsVersion')"
    $Support = "$(& $Get 'WindowsSupport')"
    $Ends = "$(& $Get 'WindowsSupportEnds')"
    if ($Support -eq 'Unsupported') { & $AddTo (& $Flag 'windowsUnsupported') "$Version no longer gets security updates" }
    elseif ($Ends) {
        $EndDate = [datetime]::MinValue
        if ([datetime]::TryParse($Ends, [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$EndDate)) {
            $DaysLeft = [int][math]::Floor(($EndDate - (Get-Date).ToUniversalTime()).TotalDays)
            if ($DaysLeft -ge 0) { & $AddTo (& $Below 'windowsEnding' $DaysLeft) "$Version security updates end $Ends" }
        }
    }
    if ([bool](& $Get 'IsHomeEdition')) { & $AddTo (& $Flag 'windowsHome') 'Windows Home edition' }

    $UpdateStatus = "$(& $Get 'UpdateStatus')"
    $SecWaiting = & $Num (& $Get 'SecurityUpdatesWaiting')
    if ($null -eq $SecWaiting -and $UpdateStatus -eq 'Behind') { $SecWaiting = 1; $SecNote = 'behind on Windows updates' }
    else { $SecNote = "$SecWaiting security update$(if ($SecWaiting -ne 1) { 's' }) waiting" }
    & $AddTo (& $Above 'securityUpdates' $SecWaiting) $SecNote
    $Failed = & $Num (& $Get 'UpdatesFailed')
    if ($null -eq $Failed -and $UpdateStatus -eq 'Failing') { $Failed = 1 }
    $FailingText = "$(& $Get 'UpdatesFailing')"
    & $AddTo (& $Above 'updatesFailing' $Failed) "update failing to install$(if ($FailingText) { " ($FailingText)" })"

    $DaysSeen = & $Num (& $Get 'DaysSinceSeen')
    & $AddTo (& $Above 'notSeen' $DaysSeen) "not seen for $DaysSeen days"
    $DaysReboot = & $Num (& $Get 'DaysSinceReboot')
    $NotSeenLevel = & $Above 'notSeen' $DaysSeen
    if ($NotSeenLevel -ne 'attention') {
        # A computer missing for a long time is reported for that; its restart age adds nothing.
        & $AddTo (& $Above 'notRestarted' $DaysReboot) $(if ($NotSeenLevel) { "had not restarted for $DaysReboot days when last seen" } else { "not restarted for $DaysReboot days" })
    }

    foreach ($Part in @("$(& $Get 'Drives')" -split ';\s*' | Where-Object { $_ })) {
        if ($Part -match '^(\S+)\s+(\d+)%') {
            & $AddTo (& $Above 'driveFull' ([int]$Matches[2])) "$($Matches[1]) $($Matches[2])% full"
        }
    }
    $MemDays = if ($PSBoundParameters.ContainsKey('MemoryDays') -and $null -ne $MemoryDays) { [int]$MemoryDays } else { & $Num (& $Get 'MemoryHighDays') }
    if ($MemDays) {
        $Threshold = if ($R['memoryThreshold']) { $R['memoryThreshold'].value } else { 90 }
        & $AddTo (& $Above 'memoryDays' $MemDays) "memory over $Threshold% in working hours on $MemDays day$(if ($MemDays -ne 1) { 's' })"
    }

    foreach ($N in $HwAttention) { $Attention.Add($N) }
    foreach ($N in $HwCheck) { $Check.Add($N) }
    $Health = if ($Attention.Count -gt 0) { 'Needs attention' } elseif ($Check.Count -gt 0) { 'Check' } else { 'Good' }

    [pscustomobject]@{
        HardwareRating = $HardwareRating
        HardwareNotes  = (@($HwAttention) + @($HwCheck)) -join '; '
        IsVirtual      = [bool]$IsVirtual
        HardwareTier   = switch ($HardwareRating) { 'Needs attention' { 'Below baseline' } 'Check' { 'Borderline' } default { 'Meets baseline' } }
        HealthStatus   = $Health
        HealthNotes    = (@($Attention) + @($Check)) -join '; '
    }
}
