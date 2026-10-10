function Get-CIPPCustomerReportData {
    <#
    .SYNOPSIS
        Gathers everything the customer report and the pre-check need for one tenant and period.

    .DESCRIPTION
        Reads only the CIPP Reporting DB (the nightly cache CIPP's own reports use) - no live Graph
        or Atera calls - so generating a report is fast and repeatable. Each source is read
        defensively: a missing source sets its section to $null and the report drops it.

        Microsoft 365 (from CIPP's cache): Users, Guests, MFAState, SecureScore, LicenseOverview,
        ManagedDevices, MailboxUsage, DomainAnalyser. Atera (from the Atera integration's nightly
        sync): AteraCustomer, AteraAgents (with the device insights the sync adds - see
        Get-AteraDeviceInsight; worked out here for data synced before insights existed),
        AteraAlerts, AteraTickets, AteraContracts, AteraPurchases.

    .PARAMETER TenantFilter
        Tenant default domain.

    .PARAMETER Period
        Output of Get-CIPPReportPeriod.

    .PARAMETER Now
        Reference time for "days since" calculations (for tests).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TenantFilter,
        [Parameter(Mandatory = $true)]$Period,
        [datetime]$Now = (Get-Date).ToUniversalTime()
    )

    function Read-Db([string]$Type) {
        try { return @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Type | Where-Object { $null -ne $_ }) }
        catch { Write-Information "Report data: $Type unavailable for $TenantFilter - $($_.Exception.Message)"; return @() }
    }
    function ConvertTo-Utc($Value) {
        if ($null -eq $Value -or "$Value" -eq '') { return $null }
        try { return ([datetime]$Value).ToUniversalTime() } catch { return $null }
    }
    function Get-OsFamily([string]$Os) {
        switch -Regex ($Os) {
            'Windows 11' { 'Windows 11'; break }
            'Windows 10' { 'Windows 10'; break }
            'Windows 8' { 'Windows 8'; break }
            'Windows 7' { 'Windows 7'; break }
            'Windows Server (\d{4})' { "Windows Server $($Matches[1])"; break }
            'Windows Server' { 'Windows Server'; break }
            'mac|Mac|Darwin' { 'macOS'; break }
            default { if ($Os) { $Os } else { 'Unknown' } }
        }
    }
    # Operating systems Microsoft no longer supports (as at 2026).
    $UnsupportedOs = '^(Windows 10|Windows 8|Windows 7|Windows Server 2008|Windows Server 2012)$'

    $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter } | Select-Object -First 1
    $TenantName = if ($Tenant.displayName) { $Tenant.displayName } else { $TenantFilter }

    # ------------------------------------------------------------------ Microsoft 365
    $Users = @(Read-Db 'Users')
    $M365 = $null
    if ($Users.Count -gt 0) {
        # People, not mailboxes: shared, room and other non-user mailboxes have enabled accounts too.
        $NonPersonUpns = @{}
        foreach ($Mbx in @(Read-Db 'Mailboxes' | Where-Object { "$($_.recipientTypeDetails)" -match 'Shared|Room|Equipment|Scheduling|Discovery' })) {
            if ($Mbx.UPN) { $NonPersonUpns["$($Mbx.UPN)".ToLowerInvariant()] = $true }
        }
        $Members = @($Users | Where-Object { $_.accountEnabled -eq $true -and $_.userType -ne 'Guest' -and $_.isResourceAccount -ne $true -and -not $NonPersonUpns.ContainsKey("$($_.userPrincipalName)".ToLowerInvariant()) })
        # Licensed = holds a paid licence (the SKUs in the licence table); free ones like Power Automate Free don't count.
        $PaidSkus = @{}
        foreach ($Sku in @(Read-Db 'LicenseOverview' | Where-Object { [int]$_.TotalLicenses -gt 0 -and [int]$_.TotalLicenses -lt 10000 })) { if ($Sku.skuId) { $PaidSkus["$($Sku.skuId)"] = $true } }
        $Licensed = @($Members | Where-Object { $u = $_; if ($PaidSkus.Count -gt 0) { @($u.assignedLicenses | Where-Object { $PaidSkus.ContainsKey("$($_.skuId)") }).Count -gt 0 } else { @($u.assignedLicenses).Count -gt 0 } })
        $Guests = @(Read-Db 'Guests')

        # MFA - same definition CIPP's SMB1001 test uses: protected when enforced by Conditional
        # Access, Security Defaults or per-user MFA.
        $Mfa = $null
        $MfaRows = @(Read-Db 'MFAState' | Where-Object { $_.AccountEnabled -eq $true -and $_.UserType -ne 'Guest' -and -not $NonPersonUpns.ContainsKey("$($_.UPN)".ToLowerInvariant()) })
        if ($MfaRows.Count -gt 0) {
            $Unprotected = @($MfaRows | Where-Object { "$($_.CoveredByCA)" -notlike 'Enforced*' -and $_.CoveredBySD -ne $true -and $_.PerUser -notin @('Enforced', 'Enabled') })
            $BreakGlass = '(?i)break.?glass|emergency.?access|emergencyaccess'
            $UnprotectedLicensed = @($Unprotected | Where-Object { $_.isLicensed -eq $true -and "$($_.DisplayName) $($_.UPN)" -notmatch $BreakGlass })
            $Mfa = @{
                Users               = $MfaRows.Count
                Protected           = $MfaRows.Count - $Unprotected.Count
                Unprotected         = $Unprotected.Count
                Registered          = @($MfaRows | Where-Object { $_.MFARegistration -eq $true }).Count
                # Protected only because Microsoft's Security Defaults are on (no Conditional Access or per-user MFA).
                ViaSecurityDefaults = @($MfaRows | Where-Object { $_.CoveredBySD -eq $true -and "$($_.CoveredByCA)" -notlike 'Enforced*' -and $_.PerUser -notin @('Enforced', 'Enabled') }).Count
                # Break-glass (emergency access) accounts are usually excluded from MFA on purpose: listed separately.
                UnprotectedAdmins   = @($Unprotected | Where-Object { $_.IsAdmin -eq $true -and "$($_.DisplayName) $($_.UPN)" -notmatch $BreakGlass } | ForEach-Object { $_.DisplayName })
                BreakGlassAdmins    = @($Unprotected | Where-Object { $_.IsAdmin -eq $true -and "$($_.DisplayName) $($_.UPN)" -match $BreakGlass } | ForEach-Object { $_.DisplayName })
                UnprotectedLicensed = @($UnprotectedLicensed | Sort-Object DisplayName | ForEach-Object { @{ name = $_.DisplayName; upn = $_.UPN } })
            }
        }

        $SecureScore = $null
        $Scores = @(Read-Db 'SecureScore' | Sort-Object -Property @{ Expression = { [datetime]$_.createdDateTime } })
        if ($Scores.Count -gt 0) {
            $Latest = $Scores[-1]
            $Cur = [double]($Latest.currentScore ?? 0)
            $Max = [double]($Latest.maxScore ?? 0)
            $Baseline = $Scores | Where-Object { (ConvertTo-Utc $_.createdDateTime) -le $Period.Start.AddDays(1) } | Select-Object -Last 1
            if (-not $Baseline) { $Baseline = $Scores[0] }
            $Similar = (@($Latest.averageComparativeScores) | Where-Object { $_.basis -eq 'TotalSeats' } | Select-Object -First 1).averageScore
            $SecureScore = @{
                Current       = [math]::Round($Cur, 1)
                Max           = $Max
                Percent       = $(if ($Max -gt 0) { [math]::Round(($Cur / $Max) * 100) } else { 0 })
                Change        = [math]::Round($Cur - [double]($Baseline.currentScore ?? $Cur), 1)
                ChangeSince   = (ConvertTo-Utc $Baseline.createdDateTime)
                SimilarPercent = $(if ($null -ne $Similar -and $Max -gt 0) { [math]::Round([double]$Similar) } else { $null })
                Trend         = @($Scores | Select-Object -Last 8 | ForEach-Object {
                        @{ label = ([datetime]$_.createdDateTime).ToString('d MMM'); value = [math]::Round([double]($_.currentScore ?? 0), 1) }
                    })
            }
        }

        $Licences = @(Read-Db 'LicenseOverview' | Where-Object { [int]$_.TotalLicenses -gt 0 -and [int]$_.TotalLicenses -lt 10000 } |
                Sort-Object -Property @{ Expression = { [int]$_.TotalLicenses } } -Descending | ForEach-Object {
                    @{ name = "$($_.License)"; used = [int]$_.CountUsed; total = [int]$_.TotalLicenses; available = [math]::Max(0, [int]$_.CountAvailable); over = [math]::Max(0, - [int]$_.CountAvailable) }
                })

        $ManagedDevices = @(Read-Db 'ManagedDevices')
        $Intune = $null
        if ($ManagedDevices.Count -gt 0) {
            $Intune = @{
                Total        = $ManagedDevices.Count
                Compliant    = @($ManagedDevices | Where-Object { $_.complianceState -eq 'compliant' }).Count
                NonCompliant = @($ManagedDevices | Where-Object { $_.complianceState -eq 'noncompliant' }).Count
            }
        }

        # Mailboxes close to the size at which they stop sending.
        $Mailboxes = @(Read-Db 'MailboxUsage' | Where-Object { [double]($_.prohibitSendQuotaInBytes ?? 0) -gt 0 -and $_.isDeleted -ne $true } | ForEach-Object {
                $Used = [double]($_.storageUsedInBytes ?? 0); $Quota = [double]$_.prohibitSendQuotaInBytes
                @{ name = "$(if ($_.displayName) { $_.displayName } else { $_.userPrincipalName })"; upn = "$($_.userPrincipalName)"; usedGB = [math]::Round($Used / 1GB, 1); quotaGB = [math]::Round($Quota / 1GB); percent = [int][math]::Round(100 * $Used / $Quota); archive = [bool]$_.hasArchive; shared = ("$($_.recipientType)" -eq 'Shared') }
            } | Sort-Object { $_.percent } -Descending)

        # Email security per domain (CIPP's domain analyser), customer wording.
        $Domains = @(Read-Db 'DomainAnalyser' | Where-Object { "$($_.Domain)" -notmatch '\.onmicrosoft\.com$' } | ForEach-Object {
                $Spf = [bool]$_.SPFPassAll
                $Dmarc = [bool]$_.DMARCPresent
                $Policy = "$($_.DMARCActionPolicy)"
                $Dkim = [bool]$_.DKIMEnabled
                $ReceivesMail = [bool]$_.MXPassTest
                $Issues = [System.Collections.Generic.List[string]]::new()
                if (-not $Spf) { $Issues.Add('no valid SPF record') }
                if (-not $Dmarc) { $Issues.Add('no DMARC policy') } elseif ($Policy -notin @('Reject', 'Quarantine')) { $Issues.Add('DMARC set to monitor only') }
                if ($ReceivesMail -and -not $Dkim) { $Issues.Add('DKIM signing off') }
                @{
                    domain   = "$($_.Domain)"
                    inUse    = $ReceivesMail
                    spf      = $Spf
                    dmarc    = $(if ($Dmarc) { $(if ($Policy) { $Policy } else { 'Present' }) } else { 'None' })
                    dkim     = $Dkim
                    score    = [int]($_.ScorePercentage ?? 0)
                    issues   = @($Issues)
                    verdict  = $(if ($Issues.Count -eq 0) { 'Protected' } elseif ($ReceivesMail) { 'Needs work' } else { 'Unused - lock down' })
                }
            } | Sort-Object { -not $_.inUse }, { $_.domain })

        # Shared mailboxes holding a paid licence: under 50 GB without an archive they do not need one.
        $SharedLicensed = @($Users | Where-Object { $NonPersonUpns.ContainsKey("$($_.userPrincipalName)".ToLowerInvariant()) -and $PaidSkus.Count -gt 0 -and @($_.assignedLicenses | Where-Object { $PaidSkus.ContainsKey("$($_.skuId)") }).Count -gt 0 } | ForEach-Object {
                $Upn = "$($_.userPrincipalName)"
                $Box = $Mailboxes | Where-Object { $_.upn -ieq $Upn } | Select-Object -First 1
                if ($Box -and ($Box.usedGB -ge 45 -or $Box.archive)) { return }
                @{ name = "$($_.displayName)"; upn = $Upn; usedGB = $(if ($Box) { $Box.usedGB } else { $null }) }
            })

        $M365 = @{
            LicensedSharedMailboxes = @($SharedLicensed)
            Mailboxes   = @($Mailboxes)
            MailboxesNearlyFull = @($Mailboxes | Where-Object { $_.percent -ge 80 })
            Domains     = @($Domains)
            Users       = $Members.Count
            Licensed    = $Licensed.Count
            Guests      = $Guests.Count
            Mfa         = $Mfa
            SecureScore = $SecureScore
            Licences    = @($Licences)
            Unassigned  = [int](($Licences | Measure-Object -Property available -Sum).Sum)
            Intune      = $Intune
        }
    }

    # ------------------------------------------------------------------ Atera
    $AteraCustomer = @(Read-Db 'AteraCustomer') | Select-Object -First 1
    $Atera = $null
    if ($AteraCustomer) {
        $Agents = @(Read-Db 'AteraAgents')
        $AlertsAll = @(Read-Db 'AteraAlerts')
        # The sync adds the insights using every device in the Atera account (needed for update status).
        # Data synced before that existed gets them here from this customer's devices alone.
        if ($Agents.Count -gt 0 -and -not ($Agents[0].PSObject.Properties.Name -contains 'HealthStatus') -and (Get-Command Get-AteraDeviceInsight -ErrorAction SilentlyContinue)) {
            $Agents = @(Get-AteraDeviceInsight -Agents $Agents -Alerts $AlertsAll -Now $Now)
        }
        $Field = { param($Row, $Name) if ($Row.PSObject.Properties.Name -contains $Name) { $Row.$Name } }
        $PeriodAlerts = @($AlertsAll | Where-Object { $c = ConvertTo-Utc $_.Created; $c -and $c -ge $Period.Start -and $c -lt $Period.End })
        # Memory above 90% during working hours (weekdays 08:00-18:00 in the reports time zone) in the period.
        $ReportZone = 'Europe/London'
        try { $ReportZone = (Get-CIPPReportSettings).TimeZone } catch {}
        # Device rules (Reports > Device Rules) are applied here, so a change takes effect in the next report.
        $DeviceRules = $null
        try { $DeviceRules = (Get-CIPPReportDeviceRules).Rules } catch {}
        $RuleValue = { param($Id, $Default) $R = @($DeviceRules | Where-Object { $_.id -eq $Id }) | Select-Object -First 1; if ($R -and "$($R.value)" -ne '') { [int]$R.value } else { $Default } }
        $DriveRule = @($DeviceRules | Where-Object { $_.id -eq 'driveFull' }) | Select-Object -First 1
        $DriveCheck = if ($DriveRule -and "$($DriveRule.check)" -ne '') { [double]$DriveRule.check } else { 75 }
        $PeriodMemory = @{}
        if (Get-Command Get-AteraMemoryPressure -ErrorAction SilentlyContinue) {
            foreach ($M in @(Get-AteraMemoryPressure -Alerts $AlertsAll -TimeZone $ReportZone -From $Period.Start -To $Period.End -Threshold (& $RuleValue 'memoryThreshold' 90) -WorkdayStart (& $RuleValue 'workdayStart' 8) -WorkdayEnd (& $RuleValue 'workdayEnd' 18))) {
                $PeriodMemory[$(if ($M.DeviceGuid) { "g:$($M.DeviceGuid)" } else { "n:$($M.DeviceName)" })] = $M
            }
        }
        $DeviceRows = foreach ($Agent in $Agents) {
            $LastSeen = ConvertTo-Utc $Agent.LastSeen
            $LastReboot = ConvertTo-Utc $Agent.LastRebootTime
            $Os = Get-OsFamily "$($Agent.OS)"
            $SystemDisk = @($Agent.HardwareDisks) | Where-Object { "$($_.Drive)" -like 'C:*' } | Select-Object -First 1
            $FreePct = & $Field $Agent 'SystemDiskFreePercent'
            if ($null -eq $FreePct -and $SystemDisk -and [double]$SystemDisk.Total -gt 0) { $FreePct = [math]::Round(([double]$SystemDisk.Free / [double]$SystemDisk.Total) * 100) }
            $Support = "$(& $Field $Agent 'WindowsSupport')"
            $Name = "$($Agent.MachineName ?? $Agent.AgentName)"
            $Model = (@("$($Agent.Vendor)".Trim(), "$($Agent.VendorBrandModel)".Trim()) | Where-Object { $_ -and $_ -notmatch 'To Be Filled|System manufacturer|System Product' }) -join ' '
            $PeriodMem = $PeriodMemory["g:$($Agent.DeviceGuid)"] ?? $PeriodMemory["n:$Name"]
            $DaysSeenLocal = $(if ($LastSeen) { if (Get-Command ConvertTo-AteraLocalTime -ErrorAction SilentlyContinue) { [int]((ConvertTo-AteraLocalTime -Utc $Now -TimeZone $ReportZone).Date - (ConvertTo-AteraLocalTime -Utc $LastSeen -TimeZone $ReportZone).Date).TotalDays } else { [int][math]::Floor(($Now - $LastSeen).TotalDays) } } else { $null })
            # Rate with today's rules and this period's memory alerts (the sync's rating used the last 90 days).
            $Rating = $null
            if (Get-Command Get-AteraDeviceRating -ErrorAction SilentlyContinue) {
                $Rated = $Agent | Select-Object *
                $Rated | Add-Member -NotePropertyName DaysSinceSeen -NotePropertyValue $DaysSeenLocal -Force
                try { $Rating = Get-AteraDeviceRating -Device $Rated -Rules $DeviceRules -MemoryDays $(if ($PeriodMem) { [int]$PeriodMem.Days } else { 0 }) } catch { Write-Information "Device rating failed for $($Name): $($_.Exception.Message)" }
            }
            $DrivesOver = @("$(& $Field $Agent 'Drives')" -split ';\s*' | Where-Object { $_ -match '^(\S+)\s+(\d+)%' -and [int]$Matches[2] -gt $DriveCheck } | ForEach-Object { $_ -replace ' full$', '' })
            [PSCustomObject]@{
                name              = $Name
                type              = "$($Agent.DeviceType)"
                os                = $Os
                osFull            = "$($Agent.OS)"
                version           = "$(if (& $Field $Agent 'WindowsVersion') { & $Field $Agent 'WindowsVersion' } else { $Os })"
                osBuild           = "$($Agent.OSBuild)"
                online            = [bool]$Agent.Online
                lastSeen          = $LastSeen
                daysSinceSeen     = $DaysSeenLocal
                daysSinceReboot   = $(if ($LastReboot) { [int][math]::Floor(($Now - $LastReboot).TotalDays) } else { $null })
                freePct           = $FreePct
                user              = ("$($Agent.LastLoginUser)" -replace '^.*\\', '')
                model             = $Model
                cpu               = "$(& $Field $Agent 'CpuSummary')"
                memoryGB          = $(if ($Agent.Memory -and (Get-Command ConvertTo-AteraMemoryGB -ErrorAction SilentlyContinue)) { ConvertTo-AteraMemoryGB -MemoryMB $Agent.Memory } else { & $Field $Agent 'MemoryGB' })
                isVirtual         = $(if ($Rating) { [bool]$Rating.IsVirtual } else { [bool](& $Field $Agent 'IsVirtual') })
                support           = $(if ($Support) { $Support } else { 'Unknown' })
                supportEnds       = "$(& $Field $Agent 'WindowsSupportEnds')"
                updateStatus      = "$(if (& $Field $Agent 'UpdateStatus') { & $Field $Agent 'UpdateStatus' } else { 'Unknown' })"
                latestBuild       = "$(& $Field $Agent 'LatestBuild')"
                hardwareTier      = "$(if ($Rating) { $Rating.HardwareTier } else { & $Field $Agent 'HardwareTier' })"
                hardwareRating    = "$(if ($Rating) { $Rating.HardwareRating } elseif ((& $Field $Agent 'HardwareTier') -eq 'Below baseline') { 'Needs attention' } else { 'Good' })"
                cores             = $(if ($Agent.ProcessorCoresCount) { [int]$Agent.ProcessorCoresCount } else { $null })
                updateSource      = "$(& $Field $Agent 'UpdateSource')"
                patchScanDate     = (ConvertTo-Utc (& $Field $Agent 'PatchScanDate'))
                securityWaiting   = (& $Field $Agent 'SecurityUpdatesWaiting')
                otherWaiting      = (& $Field $Agent 'OtherUpdatesWaiting')
                updatesFailed     = (& $Field $Agent 'UpdatesFailed')
                lastSecurityUpdate = "$(& $Field $Agent 'LastSecurityUpdate')"
                updatesWaiting    = "$(& $Field $Agent 'UpdatesWaiting')"
                updatesFailing    = "$(& $Field $Agent 'UpdatesFailing')"
                driversWaiting    = "$(& $Field $Agent 'DriversWaiting')"
                driversFailing    = "$(& $Field $Agent 'DriversFailing')"
                securityFailed    = (& $Field $Agent 'SecurityUpdatesFailed')
                drives            = "$(& $Field $Agent 'Drives')"
                drivesOver75      = $(if ("$(& $Field $Agent 'Drives')") { $DrivesOver -join '; ' } else { "$(& $Field $Agent 'DrivesOver75')" })
                drivesOver90      = "$(& $Field $Agent 'DrivesOver90')"
                fullestDrive      = (& $Field $Agent 'FullestDrivePercent')
                memoryDays        = $(if ($PeriodMem) { [int]$PeriodMem.Days } else { 0 })
                memoryPeak        = $(if ($PeriodMem) { [int]$PeriodMem.PeakPercent } else { $null })
                memoryTopProcess  = $(if ($PeriodMem) { "$($PeriodMem.TopProcess)" } else { '' })
                hardwareNotes     = "$(if ($Rating) { $Rating.HardwareNotes } else { & $Field $Agent 'HardwareNotes' })"
                win11Ready        = "$(& $Field $Agent 'Windows11Ready')"
                isHome            = [bool](& $Field $Agent 'IsHomeEdition')
                resourceAlertDays = [int](& $Field $Agent 'ResourceAlertDays')
                alertsInPeriod    = @($PeriodAlerts | Where-Object { ($_.DeviceGuid -and $_.DeviceGuid -eq $Agent.DeviceGuid) -or (-not $_.DeviceGuid -and "$($_.DeviceName)" -eq $Name) }).Count
                health            = "$(if ($Rating) { $Rating.HealthStatus } elseif (& $Field $Agent 'HealthStatus') { & $Field $Agent 'HealthStatus' } else { 'Unknown' })"
                healthNotes       = "$(if ($Rating) { $Rating.HealthNotes } else { & $Field $Agent 'HealthNotes' })"
                unsupported       = $(if ($Support) { $Support -eq 'Unsupported' } else { [bool]($Os -match $UnsupportedOs) })
            }
        }
        $DeviceRows = @($DeviceRows)
        $Active = @($DeviceRows | Where-Object { $null -eq $_.daysSinceSeen -or $_.daysSinceSeen -lt 30 })
        $HealthOrder = @{ 'Needs attention' = 0; 'Check' = 1; 'Good' = 2; 'Unknown' = 3 }

        $Alerts = $PeriodAlerts
        # Atera opens a new ticket when someone replies to a notification with the subject changed
        # ("RE: [#13006] Adobe"); those are replies, not new requests.
        $IsReplyTicket = { param($T) "$($T.TicketTitle)" -match '^\s*(RE|FW|FWD|AW|SV)\s*:\s*\[#\d+\]' }
        $TicketsRaw = @(Read-Db 'AteraTickets')
        # Tickets raised by an automated sender (Microsoft Defender, Azure notices and other no-reply
        # addresses) are not requests from the customer: counted separately.
        $IsAutomated = { param($T) "$($T.EndUserEmail)" -match '^[^@]*(no-?reply|donotreply|do-not-reply|notification|alerts?|mailer-daemon|postmaster)[^@]*@' }
        $AutomatedAll = @($TicketsRaw | Where-Object { -not (& $IsReplyTicket $_) -and (& $IsAutomated $_) })
        $TicketsAll = @($TicketsRaw | Where-Object { -not (& $IsReplyTicket $_) -and -not (& $IsAutomated $_) })
        $ReplyTickets = @($TicketsRaw | Where-Object { & $IsReplyTicket $_ } | ForEach-Object { "#$($_.TicketID): $($_.TicketTitle)" })
        $Tickets = @($TicketsAll | Where-Object { $c = ConvertTo-Utc $_.TicketCreatedDate; $c -and $c -ge $Period.Start -and $c -lt $Period.End })
        $OpenNow = @($TicketsAll | Where-Object { $_.TicketStatus -in @('Open', 'Pending') })
        $Automated = @($AutomatedAll | Where-Object { $c = ConvertTo-Utc $_.TicketCreatedDate; $c -and $c -ge $Period.Start -and $c -lt $Period.End })
        $Contracts = @(Read-Db 'AteraContracts')
        $PurchaseRows = @(Read-Db 'AteraPurchases' | ForEach-Object {
                @{ date = (ConvertTo-Utc $_.InvoiceDate); invoice = "$($_.InvoiceNumber)"; item = "$($_.Item)"; details = "$($_.Details)"; quantity = [double]($_.Quantity ?? 0); total = [double]($_.Total ?? 0); currency = "$($_.Currency)" }
            } | Where-Object { $_.date } | Sort-Object { $_.date } -Descending)
        $YearAgo = $Period.End.AddMonths(-12)

        $Atera = @{
            Customer         = "$($AteraCustomer.CustomerName)"
            Devices          = @{
                Total          = $DeviceRows.Count
                Active         = $Active.Count
                ByType         = @($DeviceRows | Group-Object type | Sort-Object Count -Descending | ForEach-Object { @{ label = $(if ($_.Name) { $_.Name } else { 'Other' }); value = $_.Count } })
                ByOs           = @($Active | Group-Object os | Sort-Object Count -Descending | ForEach-Object { @{ label = $_.Name; value = $_.Count } })
                NotSeen30      = @($DeviceRows | Where-Object { $_.daysSinceSeen -ge 30 } | Sort-Object daysSinceSeen -Descending)
                Unsupported    = @($Active | Where-Object unsupported | Sort-Object name)
                LowDisk        = @($Active | Where-Object { $null -ne $_.freePct -and $_.freePct -lt 10 } | Sort-Object freePct)
                NotRebooted30  = @($Active | Where-Object { $_.online -and $_.daysSinceReboot -ge 30 } | Sort-Object daysSinceReboot -Descending)
                DuplicateNames = @($DeviceRows | Group-Object name | Where-Object { $_.Count -gt 1 -and $_.Name } | ForEach-Object { $_.Name })
                List           = @($DeviceRows | Sort-Object { $HealthOrder["$($_.health)"] }, name)
                Healthy        = @($Active | Where-Object { $_.health -eq 'Good' }).Count
                UpToDate       = @($Active | Where-Object { $_.updateStatus -eq 'Up to date' }).Count
                UpdatesBehind  = @($Active | Where-Object { $_.updateStatus -eq 'Behind' } | Sort-Object name)
                UpdatesUnknown = @($Active | Where-Object { $_.updateStatus -notin @('Up to date', 'Behind') }).Count
                SupportEnding  = @($Active | Where-Object { $_.support -eq 'Ending soon' } | Sort-Object name)
                BelowBaseline  = @($Active | Where-Object { $_.hardwareRating -eq 'Needs attention' } | Sort-Object name)
                HardwareCheck  = @($Active | Where-Object { $_.hardwareRating -eq 'Check' } | Sort-Object name)
                DriveThreshold = $DriveCheck
                MemoryThreshold = (& $RuleValue 'memoryThreshold' 90)
                WorkdayStart   = (& $RuleValue 'workdayStart' 8)
                WorkdayEnd     = (& $RuleValue 'workdayEnd' 18)
                MemoryPressure = @($Active | Where-Object { $_.memoryDays -gt 0 } | Sort-Object memoryDays -Descending)
                StorageOver75  = @($Active | Where-Object { $_.drivesOver75 } | Sort-Object { - [int]$_.fullestDrive })
                UpdatesFailing = @($Active | Where-Object { $_.updateStatus -eq 'Failing' } | Sort-Object name)
                PatchScanned   = @($Active | Where-Object { $_.updateSource -eq 'Atera patch scan' }).Count
                HomeEdition    = @($Active | Where-Object isHome | Sort-Object name)
                NotWin11Ready  = @($Active | Where-Object { $_.os -eq 'Windows 10' -and $_.win11Ready -eq 'No' } | Sort-Object name)
                AlertsByDevice = @($DeviceRows | Where-Object { $_.alertsInPeriod -gt 0 } | Sort-Object alertsInPeriod -Descending)
            }
            Alerts           = @{
                Total      = $Alerts.Count
                Last90     = $AlertsAll.Count
                BySeverity = @($Alerts | Group-Object Severity | Sort-Object Count -Descending | ForEach-Object { @{ label = $(if ($_.Name) { $_.Name } else { 'Unknown' }); value = $_.Count } })
                TopTitles  = @($Alerts | Group-Object Title | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { @{ title = $_.Name; count = $_.Count; devices = @($_.Group.DeviceName | Select-Object -Unique).Count } })
            }
            Tickets          = @{
                Opened        = $Tickets.Count
                Resolved      = @($Tickets | Where-Object { $_.TicketStatus -in @('Closed', 'Resolved') }).Count
                OpenNow       = $OpenNow.Count
                MinutesLogged = [math]::Round((($Tickets | Measure-Object -Property TotalDurationSeconds -Sum).Sum ?? 0) / 60)
                ByRequester   = @($Tickets | Group-Object { "$($_.EndUserFirstName)".Trim() } | Where-Object Name | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { @{ label = $_.Name; value = $_.Count } })
                List          = @($Tickets | Sort-Object { ConvertTo-Utc $_.TicketCreatedDate } | ForEach-Object {
                        @{
                            number  = "$($_.TicketID)"
                            title   = "$($_.TicketTitle)"
                            status  = "$($_.TicketStatus)"
                            created = (ConvertTo-Utc $_.TicketCreatedDate)
                            minutes = [math]::Round([double]($_.TotalDurationSeconds ?? 0) / 60)
                            priority = "$($_.TicketPriority)"
                            requester = ("$($_.EndUserFirstName) $($_.EndUserLastName)".Trim())
                        }
                    })
                OldUrgent     = @($OpenNow | Where-Object { $_.TicketPriority -in @('High', 'Critical') -and (ConvertTo-Utc $_.TicketCreatedDate) -lt $Now.AddDays(-14) } | ForEach-Object { "#$($_.TicketID): $($_.TicketTitle)" })
                ReplyTickets  = @($ReplyTickets)
                Automated     = $Automated.Count
                AutomatedMinutes = [math]::Round((($Automated | Measure-Object -Property TotalDurationSeconds -Sum).Sum ?? 0) / 60)
                AutomatedFrom = @($Automated | Group-Object { "$($_.EndUserFirstName) $($_.EndUserLastName)".Trim() } | Sort-Object Count -Descending | ForEach-Object { $_.Name })
                AutomatedOpen = @($AutomatedAll | Where-Object { $_.TicketStatus -in @('Open', 'Pending') }).Count
                NoTimeClosed  = @($Tickets | Where-Object { $_.TicketStatus -in @('Closed', 'Resolved') -and [double]($_.TotalDurationSeconds ?? 0) -le 0 } | ForEach-Object { "#$($_.TicketID): $($_.TicketTitle)" })
            }
            Purchases        = @{
                Period      = @($PurchaseRows | Where-Object { $_.date -ge $Period.Start -and $_.date -lt $Period.End })
                Year        = @($PurchaseRows | Where-Object { $_.date -ge $YearAgo -and $_.date -lt $Period.End })
                YearTotal   = [math]::Round(((@($PurchaseRows | Where-Object { $_.date -ge $YearAgo -and $_.date -lt $Period.End }) | ForEach-Object { $_.total }) | Measure-Object -Sum).Sum ?? 0, 2)
                PeriodTotal = [math]::Round(((@($PurchaseRows | Where-Object { $_.date -ge $Period.Start -and $_.date -lt $Period.End }) | ForEach-Object { $_.total }) | Measure-Object -Sum).Sum ?? 0, 2)
                Currency    = "$(@($PurchaseRows | Where-Object { $_.currency } | Select-Object -First 1).currency)"
                Available   = $PurchaseRows.Count -gt 0
            }
            Contracts        = @{
                Active = @($Contracts | Where-Object { $_.Active -eq $true } | ForEach-Object {
                        @{ name = "$($_.ContractName)"; type = "$($_.ContractType)"; end = (ConvertTo-Utc $_.EndDate) }
                    })
            }
        }
        $Atera.Contracts.EndingSoon = @($Atera.Contracts.Active | Where-Object { $_.end -and $_.end -ge $Now -and $_.end -le $Now.AddDays(60) })
    }

    return @{
        TenantName   = $TenantName
        TenantFilter = $TenantFilter
        TenantId     = $Tenant.customerId
        GraphError   = "$($Tenant.LastGraphError)"
        Period       = $Period
        GeneratedAt  = $Now
        M365         = $M365
        Atera        = $Atera
    }
}
