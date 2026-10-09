function Get-CIPPCustomerReportData {
    <#
    .SYNOPSIS
        Gathers everything the customer report and the pre-check need for one tenant and period.

    .DESCRIPTION
        Reads only the CIPP Reporting DB (the nightly cache CIPP's own reports use) - no live Graph
        or Atera calls - so generating a report is fast and repeatable. Each source is read
        defensively: a missing source sets its section to $null and the report drops it.

        Microsoft 365 (from CIPP's cache): Users, Guests, MFAState, SecureScore, LicenseOverview,
        ManagedDevices. Atera (from the Atera integration's nightly sync): AteraCustomer,
        AteraAgents, AteraAlerts, AteraTickets, AteraContracts.

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
        $Members = @($Users | Where-Object { $_.accountEnabled -eq $true -and $_.userType -ne 'Guest' -and $_.isResourceAccount -ne $true })
        $Licensed = @($Members | Where-Object { @($_.assignedLicenses).Count -gt 0 })
        $Guests = @(Read-Db 'Guests')

        # MFA - same definition CIPP's SMB1001 test uses: protected when enforced by Conditional
        # Access, Security Defaults or per-user MFA.
        $Mfa = $null
        $MfaRows = @(Read-Db 'MFAState' | Where-Object { $_.AccountEnabled -eq $true -and $_.UserType -ne 'Guest' })
        if ($MfaRows.Count -gt 0) {
            $Unprotected = @($MfaRows | Where-Object { "$($_.CoveredByCA)" -notlike 'Enforced*' -and $_.CoveredBySD -ne $true -and $_.PerUser -notin @('Enforced', 'Enabled') })
            $UnprotectedLicensed = @($Unprotected | Where-Object { $_.isLicensed -eq $true })
            $Mfa = @{
                Users               = $MfaRows.Count
                Protected           = $MfaRows.Count - $Unprotected.Count
                Unprotected         = $Unprotected.Count
                Registered          = @($MfaRows | Where-Object { $_.MFARegistration -eq $true }).Count
                UnprotectedAdmins   = @($Unprotected | Where-Object { $_.IsAdmin -eq $true } | ForEach-Object { $_.DisplayName })
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
                    @{ name = "$($_.License)"; used = [int]$_.CountUsed; total = [int]$_.TotalLicenses; available = [int]$_.CountAvailable }
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

        $M365 = @{
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
        $DeviceRows = foreach ($Agent in $Agents) {
            $LastSeen = ConvertTo-Utc $Agent.LastSeen
            $LastReboot = ConvertTo-Utc $Agent.LastRebootTime
            $Os = Get-OsFamily "$($Agent.OS)"
            $SystemDisk = @($Agent.HardwareDisks) | Where-Object { "$($_.Drive)" -like 'C:*' } | Select-Object -First 1
            $FreePct = $null
            if ($SystemDisk -and [double]$SystemDisk.Total -gt 0) { $FreePct = [math]::Round(([double]$SystemDisk.Free / [double]$SystemDisk.Total) * 100) }
            [PSCustomObject]@{
                name            = "$($Agent.MachineName ?? $Agent.AgentName)"
                type            = "$($Agent.DeviceType)"
                os              = $Os
                osFull          = "$($Agent.OS)"
                online          = [bool]$Agent.Online
                lastSeen        = $LastSeen
                daysSinceSeen   = $(if ($LastSeen) { [int][math]::Floor(($Now - $LastSeen).TotalDays) } else { $null })
                daysSinceReboot = $(if ($LastReboot) { [int][math]::Floor(($Now - $LastReboot).TotalDays) } else { $null })
                freePct         = $FreePct
                user            = "$($Agent.LastLoginUser)"
                unsupported     = [bool]($Os -match $UnsupportedOs)
            }
        }
        $DeviceRows = @($DeviceRows)
        $Active = @($DeviceRows | Where-Object { $null -eq $_.daysSinceSeen -or $_.daysSinceSeen -lt 30 })

        $Alerts = @(Read-Db 'AteraAlerts' | Where-Object { $c = ConvertTo-Utc $_.Created; $c -and $c -ge $Period.Start -and $c -lt $Period.End })
        $TicketsAll = @(Read-Db 'AteraTickets')
        $Tickets = @($TicketsAll | Where-Object { $c = ConvertTo-Utc $_.TicketCreatedDate; $c -and $c -ge $Period.Start -and $c -lt $Period.End })
        $OpenNow = @($TicketsAll | Where-Object { $_.TicketStatus -in @('Open', 'Pending') })
        $Contracts = @(Read-Db 'AteraContracts')

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
            }
            Alerts           = @{
                Total      = $Alerts.Count
                BySeverity = @($Alerts | Group-Object Severity | Sort-Object Count -Descending | ForEach-Object { @{ label = $(if ($_.Name) { $_.Name } else { 'Unknown' }); value = $_.Count } })
                TopTitles  = @($Alerts | Group-Object Title | Sort-Object Count -Descending | Select-Object -First 6 | ForEach-Object { @{ title = $_.Name; count = $_.Count; devices = @($_.Group.DeviceName | Select-Object -Unique).Count } })
            }
            Tickets          = @{
                Opened        = $Tickets.Count
                Resolved      = @($Tickets | Where-Object { $_.TicketStatus -in @('Closed', 'Resolved') }).Count
                OpenNow       = $OpenNow.Count
                MinutesLogged = [math]::Round((($Tickets | Measure-Object -Property TotalDurationSeconds -Sum).Sum ?? 0) / 60)
                List          = @($Tickets | Sort-Object { ConvertTo-Utc $_.TicketCreatedDate } | ForEach-Object {
                        @{
                            number  = "$($_.TicketID)"
                            title   = "$($_.TicketTitle)"
                            status  = "$($_.TicketStatus)"
                            created = (ConvertTo-Utc $_.TicketCreatedDate)
                            minutes = [math]::Round([double]($_.TotalDurationSeconds ?? 0) / 60)
                            priority = "$($_.TicketPriority)"
                        }
                    })
                OldUrgent     = @($OpenNow | Where-Object { $_.TicketPriority -in @('High', 'Critical') -and (ConvertTo-Utc $_.TicketCreatedDate) -lt $Now.AddDays(-14) } | ForEach-Object { "#$($_.TicketID): $($_.TicketTitle)" })
                NoTimeClosed  = @($Tickets | Where-Object { $_.TicketStatus -in @('Closed', 'Resolved') -and [double]($_.TotalDurationSeconds ?? 0) -le 0 } | ForEach-Object { "#$($_.TicketID): $($_.TicketTitle)" })
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
