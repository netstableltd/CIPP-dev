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
        param($Id, $Severity, $Area, $Title, $Detail, $Items = @(), $Customer = $null)
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
            })
    }
    $Plural = { param($n, $word) "$n $word$(if ($n -ne 1) { 's' })" }

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
                "Enforce multi-factor authentication for the $(& $Plural $Mfa.UnprotectedLicensed.Count 'remaining user')."
        }
        $Score = $Data.M365.SecureScore
        if ($Score -and $Score.Change -le -5) {
            Add-Finding 'securescore-drop' 'Fix' 'Microsoft 365' 'Secure Score dropped' "Secure Score fell by $([math]::Abs($Score.Change)) points since $($Score.ChangeSince.ToString('d MMM')). Check for disabled policies or new uncovered controls." @() `
                'Your Microsoft Secure Score dropped this month. We are reviewing the cause.'
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
            Add-Finding 'devices-unsupported-os' 'Fix' 'Devices' 'Unsupported operating systems' "$(& $Plural $D.Unsupported.Count 'device') run an operating system Microsoft no longer supports. Have an upgrade or replacement proposal ready." @($D.Unsupported | ForEach-Object { "$($_.name) ($($_.os))" }) `
                "Upgrade or replace the $(& $Plural $D.Unsupported.Count 'device') running an operating system that no longer receives security updates."
        }
        if ($D.LowDisk.Count -gt 0) {
            Add-Finding 'devices-low-disk' 'Fix' 'Devices' 'System drive under 10% free' "$(& $Plural $D.LowDisk.Count 'device') are nearly out of disk space on C:." @($D.LowDisk | ForEach-Object { "$($_.name) ($($_.freePct)% free)" }) `
                "Free up or add storage on the $(& $Plural $D.LowDisk.Count 'device') that are almost full."
        }
        if ($D.NotRebooted30.Count -gt 0) {
            Add-Finding 'devices-no-reboot' 'Fix' 'Devices' 'Online but not restarted for 30+ days' "$(& $Plural $D.NotRebooted30.Count 'device') have pending updates that need a restart." @($D.NotRebooted30 | ForEach-Object { "$($_.name) ($($_.daysSinceReboot) days)" }) `
                "Restart the $(& $Plural $D.NotRebooted30.Count 'device') that have not been restarted for over a month so updates can finish installing."
        }

        $T = $Data.Atera.Tickets
        if ($T.OldUrgent.Count -gt 0) {
            Add-Finding 'tickets-old-urgent' 'Fix' 'Support' 'High/Critical tickets open over 14 days' 'Resolve or update these before the customer sees the report.' $T.OldUrgent
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
