function Get-CIPPReportFindings {
    <#
    .SYNOPSIS
        Runs the pre-check rules against one company's report data.

    .DESCRIPTION
        Severities:
          Block - the customer report would be wrong or empty; it is held until fixed or overridden.
          Fix   - should be sorted before the report goes out; shown to the customer as a
                  recommendation if still open.
          Info  - worth knowing internally; not shown to the customer.

        Each finding: Id, Severity, Area, Title, Detail (internal wording), Count, Items (names),
        Customer (customer-facing recommendation wording, or $null when internal only).

    .PARAMETER Data
        Output of Get-CIPPCustomerReportData.

    .PARAMETER AteraEnabled
        Whether the Atera integration is in use (a missing mapping only matters then).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Data,
        [bool]$AteraEnabled = $true
    )

    $Findings = [System.Collections.Generic.List[object]]::new()
    function Add-Finding {
        param($Id, $Severity, $Area, $Title, $Detail, $Items = @(), $Customer = $null, $CustomerItems = $null)
        $List = @($Items | Where-Object { $_ })
        $Findings.Add([PSCustomObject]@{
                Id       = $Id
                Severity = $Severity
                Area     = $Area
                Title    = $Title
                Detail   = $Detail
                Count    = $List.Count
                Items    = $List
                Customer = $Customer
                # What the customer report lists as affected (defaults to Items; set when Items carry internal detail).
                CustomerItems = $(if ($null -ne $CustomerItems) { @($CustomerItems | Where-Object { $_ }) } else { $List })
            })
    }
    $Plural = { param($n, $word) "$n $word$(if ($n -ne 1) { 's' })" }
    # 'the computer' / 'the 3 computers' for customer wording (plural adds s, or es after s/x/ch/sh).
    $The = { param($n, $word) if ($n -eq 1) { "the $word" } elseif ($word -eq 'person') { "the $n people" } else { "the $n $($word)$(if ($word -match '(s|x|ch|sh)$') { 'es' } else { 's' })" } }
    $Are = { param($n) if ($n -eq 1) { 'is' } else { 'are' } }

    # ---------------------------------------------------------------- data quality
    if ($Data.GraphError) {
        Add-Finding 'm365-connection' 'Block' 'Data' 'Microsoft 365 connection error' "CIPP cannot reach this tenant: $($Data.GraphError). Re-consent CIPP-SAM / refresh CPV for the tenant."
    } elseif (-not $Data.M365) {
        Add-Finding 'm365-no-cache' 'Block' 'Data' 'No Microsoft 365 data cached' 'CIPP has no cached users for this tenant yet. Run a cache refresh (CIPP > Advanced > CIPPDB Cache) or wait for the nightly cache.'
    }
    if ($AteraEnabled -and -not $Data.Atera) {
        Add-Finding 'atera-mapping' 'Block' 'Data' 'Not mapped to an Atera customer' 'Map the tenant on Integrations > Atera > Tenant Mapping, then run Force Sync. If the company has no Atera presence, it can be reported on Microsoft 365 data only.'
    }

    # ---------------------------------------------------------------- Microsoft 365
    if ($Data.M365) {
        $Mfa = $Data.M365.Mfa
        if ($Mfa -and $Mfa.UnprotectedAdmins.Count -gt 0) {
            Add-Finding 'mfa-admins' 'Fix' 'Microsoft 365' 'Admin accounts without enforced MFA' "$(& $Plural $Mfa.UnprotectedAdmins.Count 'admin account') can sign in without MFA being enforced." $Mfa.UnprotectedAdmins `
                'Turn on multi-factor authentication for every administrator account. Admin accounts are the most targeted.'
        }
        if ($Mfa -and $Mfa.UnprotectedLicensed.Count -gt 0) {
            Add-Finding 'mfa-users' 'Fix' 'Microsoft 365' 'Users without enforced MFA' "$(& $Plural $Mfa.UnprotectedLicensed.Count 'licensed user') of $($Mfa.Users) are not covered by Conditional Access, Security Defaults or per-user MFA." @($Mfa.UnprotectedLicensed | ForEach-Object { $_.name }) `
                "Enforce multi-factor authentication for $(& $The $Mfa.UnprotectedLicensed.Count 'remaining user')."
        }
        $Score = $Data.M365.SecureScore
        if ($Score -and $Score.Change -le -5) {
            Add-Finding 'securescore-drop' 'Fix' 'Microsoft 365' 'Secure Score dropped' "Secure Score fell by $([math]::Abs($Score.Change)) points since $($Score.ChangeSince.ToString('d MMM')). Check for disabled policies or new uncovered controls." @() `
                'Your Microsoft Secure Score dropped this month. We are reviewing the cause.'
        }
        $Full = @($Data.M365.MailboxesNearlyFull)
        if ($Full.Count -gt 0) {
            Add-Finding 'mailbox-nearly-full' 'Fix' 'Microsoft 365' 'Mailboxes nearly full' "$(& $Plural $Full.Count 'mailbox') are at 80% or more of the size at which they stop sending." @($Full | ForEach-Object { "$($_.name) ($($_.percent)%, $($_.usedGB) of $($_.quotaGB) GB)" }) `
                "Archive or tidy $(& $The $Full.Count 'mailbox') that $(& $Are $Full.Count) nearly full before $(if ($Full.Count -eq 1) { 'it stops' } else { 'they stop' }) sending email. $(if (@($Full | Where-Object shared).Count -gt 0) { 'Turning on the online archive usually solves it; a shared mailbox needs a licence for its archive.' } else { 'Turning on the online archive, included in your licence, usually solves it.' })" @($Full | ForEach-Object { "$($_.name) ($($_.percent)% full$(if ($_.shared) { ', shared mailbox' }))" })
        }
        $WeakDomains = @($Data.M365.Domains | Where-Object { @($_.issues).Count -gt 0 })
        if ($WeakDomains.Count -gt 0) {
            Add-Finding 'domain-email-security' 'Fix' 'Microsoft 365' 'Domains with weak email security' "$(& $Plural $WeakDomains.Count 'domain') are missing SPF, DMARC or DKIM, so they are easier to spoof." @($WeakDomains | ForEach-Object { "$($_.domain): $(@($_.issues) -join ', ')" }) `
                "Finish the email security settings (SPF, DKIM and DMARC) on $(& $The $WeakDomains.Count 'domain') listed, including any domains you own but do not use, so they cannot be used to send fake email in your name. The Email & Domains page shows what each one needs." @($WeakDomains | ForEach-Object { $_.domain })
        }
        $Br = $Data.Breaches
        $People = @($Br.People)
        if ($Br -and $People.Count -gt 0) {
            Add-Finding 'accounts-breached' 'Fix' 'Microsoft 365' 'Email addresses in known data breaches' "$(& $Plural $People.Count 'person') ($(& $Plural $Br.Total 'address') in all, including aliases, shared mailboxes and old accounts) appear in known breaches of other websites; $($Br.PeopleWithPasswords) with passwords exposed. Make sure MFA is enforced for them and they don't reuse passwords." @($Br.Accounts | ForEach-Object { "$($_.email) [$($_.kind)$(if ($_.alias) { ", alias of $($_.owner)" })]: $(@($_.breaches | ForEach-Object { $_.title }) -join ', ')" }) `
                "Ask $(& $The $People.Count 'person') whose email address appears in a data breach to make sure they don't use the same password anywhere else, and that multi-factor authentication is on for their account. The breaches were of other websites, not your Microsoft 365." $People
        }
        if ($Br -and $Br.Source -eq 'None' -and $Br.Error) {
            Add-Finding 'breach-check-failed' 'Info' 'Microsoft 365' 'Breach check failed' "The breach lookup did not run: $($Br.Error)"
        }
        $SharedLic = @($Data.M365.LicensedSharedMailboxes)
        if ($SharedLic.Count -gt 0) {
            Add-Finding 'licence-shared-mailbox' 'Info' 'Microsoft 365' 'Licences on shared mailboxes' "$(& $Plural $SharedLic.Count 'shared mailbox') hold a paid licence but are under 50 GB with no archive, so they do not need one." @($SharedLic | ForEach-Object { "$($_.upn)$(if ($null -ne $_.usedGB) { " ($($_.usedGB) GB)" })" }) `
                "Remove the Microsoft 365 licence from $(& $The $SharedLic.Count 'shared mailbox'): a shared mailbox under 50 GB does not need one, so it is a saving." @($SharedLic | ForEach-Object { $_.upn })
        }
        if ($Data.M365.Unassigned -gt 0) {
            $Spare = @($Data.M365.Licences | Where-Object { $_.available -gt 0 } | ForEach-Object { "$($_.name): $($_.available) unassigned" })
            Add-Finding 'licences-unassigned' 'Info' 'Microsoft 365' 'Paid licences not assigned' "$(& $Plural $Data.M365.Unassigned 'licence') bought but not assigned. A saving, or seats for planned starters?" $Spare
        }
    }

    # ---------------------------------------------------------------- Atera devices
    if ($Data.Atera) {
        $D = $Data.Atera.Devices
        if ($D.NotSeen30.Count -gt 0) {
            Add-Finding 'devices-stale' 'Fix' 'Devices' 'Devices not seen for 30+ days' "$(& $Plural $D.NotSeen30.Count 'device') have not checked in to Atera for 30 days or more. Remove retired machines from Atera, or find out why they are offline - they are excluded from the customer's device counts." @($D.NotSeen30 | ForEach-Object { "$($_.name) ($($_.daysSinceSeen) days)" })
        }
        if ($D.DuplicateNames.Count -gt 0) {
            Add-Finding 'devices-duplicate' 'Info' 'Devices' 'Duplicate device names in Atera' 'Probably re-imaged machines with an old agent left behind.' $D.DuplicateNames
        }
        if ($D.Unsupported.Count -gt 0) {
            Add-Finding 'devices-unsupported-os' 'Fix' 'Devices' 'Unsupported operating systems' "$(& $Plural $D.Unsupported.Count 'device') run a Windows version Microsoft no longer supports. Have an upgrade or replacement proposal ready." @($D.Unsupported | ForEach-Object { "$($_.name) ($($_.version))" }) `
                "Upgrade or replace $(& $The $D.Unsupported.Count 'computer') running a version of Windows that no longer receives security updates." @($D.Unsupported | ForEach-Object { "$($_.name) ($($_.version))" })
        }
        if (@($D.SupportEnding).Count -gt 0) {
            Add-Finding 'devices-support-ending' 'Fix' 'Updates' 'Windows support ending within 90 days' "$(& $Plural @($D.SupportEnding).Count 'device') will stop receiving security updates soon unless moved to a newer Windows version (usually a free feature update)." @($D.SupportEnding | ForEach-Object { "$($_.name) ($($_.version), ends $($_.supportEnds))" }) `
                "Move $(& $The @($D.SupportEnding).Count 'computer') on a Windows version that is about to stop receiving security updates to the current version. This is a free update."
        }
        if (@($D.UpdatesBehind).Count -gt 0) {
            Add-Finding 'devices-updates-behind' 'Fix' 'Updates' 'Behind on Windows updates' "$(& $Plural @($D.UpdatesBehind).Count 'device') still need security updates (Atera patch scan, or an older build than the rest of our managed devices where there is no scan). Check patching and restarts." @($D.UpdatesBehind | ForEach-Object { if ($_.updateSource -eq 'Atera patch scan') { "$($_.name) ($($_.securityWaiting) security update$(if ([int]$_.securityWaiting -ne 1) { 's' }) waiting: $($_.updatesWaiting))" } else { "$($_.name) ($($_.osBuild), current $($_.latestBuild))" } }) `
                "Bring $(& $The @($D.UpdatesBehind).Count 'computer') that $(& $Are @($D.UpdatesBehind).Count) behind on Windows updates up to date. We will schedule this with the users." @($D.UpdatesBehind | ForEach-Object { $_.name })
        }
        if (@($D.UpdatesFailing).Count -gt 0) {
            Add-Finding 'devices-updates-failing' 'Fix' 'Updates' 'Updates failing to install' "$(& $Plural @($D.UpdatesFailing).Count 'device') have updates that failed to install (Atera patch scan)." @($D.UpdatesFailing | ForEach-Object { "$($_.name): $($_.updatesFailing)" }) `
                "Fix the updates that failed to install on $(& $The @($D.UpdatesFailing).Count 'computer')." @($D.UpdatesFailing | ForEach-Object { $_.name })
        }
        if (@($D.MemoryPressure).Count -gt 0) {
            $Mp = @($D.MemoryPressure)
            Add-Finding 'devices-memory' 'Info' 'Device health' 'Memory over 90% in working hours' "$(& $Plural $Mp.Count 'device') ran above 90% memory during working hours this period (Atera memory alerts). A memory upgrade is the usual fix." @($Mp | ForEach-Object { "$($_.name) ($($_.memoryDays) day$(if ($_.memoryDays -ne 1) { 's' }), peak $($_.memoryPeak)%$(if ($_.memoryGB) { ", $($_.memoryGB) GB RAM" })$(if ($_.memoryTopProcess) { ", mostly $($_.memoryTopProcess)" }))" }) `
                "Add more memory (RAM) to $(& $The $Mp.Count 'computer') that ran out of memory during the working day. Upgrading memory is usually inexpensive and makes a noticeable difference." @($Mp | ForEach-Object { "$($_.name)$(if ($_.memoryGB) { " ($($_.memoryGB) GB now)" })" })
        }
        $Full = @($D.StorageOver75)
        if ($Full.Count -gt 0) {
            $Critical = @($Full | Where-Object { $_.drivesOver90 })
            Add-Finding 'devices-storage' $(if ($Critical.Count -gt 0) { 'Fix' } else { 'Info' }) 'Device health' 'Drives over 75% full' "$(& $Plural $Full.Count 'device') have a drive over 75% full$(if ($Critical.Count -gt 0) { "; $($Critical.Count) over 90%" })." @($Full | ForEach-Object { "$($_.name) ($($_.drivesOver75))" }) `
                $(if ($Critical.Count -gt 0) { "Free up space now, or fit a bigger drive, on $(& $The $Full.Count 'computer') with a drive more than three-quarters full. A drive over 90% full stops updates and everyday work, so $(if ($Critical.Count -eq 1) { "$($Critical[0].name) needs" } else { 'these need' }) attention first." } else { "Free up space, by deleting or archiving old files, or fit a bigger drive in $(& $The $Full.Count 'computer') with a drive more than three-quarters full." }) @($Full | ForEach-Object { "$($_.name) ($($_.drivesOver75 -replace '%', '% full'))" })
        }
        if (@($D.BelowBaseline).Count -gt 0) {
            $Bb = @($D.BelowBaseline)
            Add-Finding 'devices-below-baseline' 'Info' 'Device health' 'Below the hardware baseline' "$(& $Plural $Bb.Count 'device') are below the baseline (a quad-core processor that can run Windows 11)." @($Bb | ForEach-Object { "$($_.name) ($($_.hardwareNotes))" }) `
                "Plan to replace or upgrade $(& $The $Bb.Count 'computer') below our minimum standard: a processor with at least four cores that can run Windows 11."
        }
        if (@($D.HomeEdition).Count -gt 0) {
            Add-Finding 'devices-home-edition' 'Info' 'Device health' 'Windows Home edition on business devices' 'Home edition cannot join Entra ID or a domain and has no BitLocker management. An upgrade to Pro is a licence key change.' @($D.HomeEdition | ForEach-Object { $_.name }) `
                "Upgrade $(& $The @($D.HomeEdition).Count 'computer') running Windows Home to Windows Pro, so $(if (@($D.HomeEdition).Count -eq 1) { 'it' } else { 'they' }) can be managed and encrypted like the rest."
        }
        if ($D.NotRebooted30.Count -gt 0) {
            Add-Finding 'devices-no-reboot' 'Fix' 'Devices' 'Online but not restarted for 30+ days' "$(& $Plural $D.NotRebooted30.Count 'device') have pending updates that need a restart." @($D.NotRebooted30 | ForEach-Object { "$($_.name) ($($_.daysSinceReboot) days)" }) `
                "Restart $(& $The $D.NotRebooted30.Count 'computer') that $(if ($D.NotRebooted30.Count -eq 1) { 'has' } else { 'have' }) not been restarted for over a month so updates can finish installing."
        }

        if ($D.Total -gt 0 -and $null -ne $Data.Atera.Alerts.Last90 -and $Data.Atera.Alerts.Last90 -eq 0) {
            Add-Finding 'monitoring-silent' 'Fix' 'Monitoring' 'No monitoring alerts in 90 days' 'Not one alert in three months usually means no threshold profile is applied to this customer in Atera, so disk, memory and CPU problems are not being alerted on (and the memory check in this report cannot fire). Check the customer''s monitoring profile.'
        }

        $T = $Data.Atera.Tickets
        if ($T.OldUrgent.Count -gt 0) {
            Add-Finding 'tickets-old-urgent' 'Fix' 'Support' 'High/Critical tickets open over 14 days' 'Resolve or update these before the customer sees the report.' $T.OldUrgent
        }
        if (@($T.ReplyTickets).Count -gt 0) {
            Add-Finding 'tickets-replies' 'Info' 'Support' 'Replies logged as new tickets' 'Left out of the customer''s request count. Merge them into the original ticket in Atera.' @($T.ReplyTickets)
        }
        if ($T.NoTimeClosed.Count -gt 0) {
            Add-Finding 'tickets-no-time' 'Fix' 'Support' 'Closed tickets with no time logged' 'These will show as zero time in the support summary (and may be unbilled).' $T.NoTimeClosed
        }
        if ($Data.Atera.Contracts.EndingSoon.Count -gt 0) {
            Add-Finding 'contracts-ending' 'Info' 'Contracts' 'Contract ending within 60 days' 'Renewal conversation due.' @($Data.Atera.Contracts.EndingSoon | ForEach-Object { "$($_.name) (ends $($_.end.ToString('d MMM yyyy')))" })
        }
    }

    $Order = @{ Block = 0; Fix = 1; Info = 2 }
    return @($Findings | Sort-Object { $Order[$_.Severity] }, Area, Title)
}
