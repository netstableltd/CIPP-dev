function Build-CippCustomerReportTree {
    <#
    .SYNOPSIS
        Composes the monthly customer report as a component tree for ConvertTo-CippReportPdf.

    .DESCRIPTION
        Sections appear only when their data exists: Microsoft 365 sections need CIPP's cache for
        the tenant, device/alert/support sections need the Atera integration. Recommendations come
        from pre-check findings that carry customer wording (Get-CIPPReportFindings).

    .PARAMETER Data
        Output of Get-CIPPCustomerReportData.

    .PARAMETER Findings
        Output of Get-CIPPReportFindings for the same data.

    .PARAMETER Summary
        Optional free-text paragraph written by the MSP (Review & Send), shown on the first page.

    .PARAMETER Sections
        Ordered section ids to include (see Get-CIPPReportSectionCatalog). Built-in ids:
        summary, m365-security, users-licences, devices, monitoring, support, recommendations.
        Empty = all built-in sections in that order.

    .PARAMETER ExtraSections
        Pre-resolved non-built-in sections keyed by id, each @{ Title; Subtitle; Blocks } -
        used for Report Builder templates ('template:<GUID>').

    .OUTPUTS
        @{ Blocks; Variables }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][hashtable]$Data,
        [object[]]$Findings = @(),
        [string]$Summary,
        [string[]]$Sections,
        [hashtable]$ExtraSections
    )

    $okC = '#22543D'; $warnC = '#744210'; $dangerC = '#742A2A'
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $plural = { param($n, $word) "$n $word$(if ($n -ne 1) { 's' })" }
    $hm = { param($minutes) $m = [int]$minutes; '{0}h {1:00}m' -f [math]::Floor($m / 60), ($m % 60) }

    $Name = $Data.TenantName
    $PeriodLabel = $Data.Period.Label
    $M = $Data.M365
    $A = $Data.Atera
    $Actions = @($Findings | Where-Object { $_.Customer -and $_.Severity -ne 'Info' })

    $blocks = [System.Collections.Generic.List[object]]::new()

    $SectionBuilders = [ordered]@{
        'summary' = {
        $blocks.Add((New-CippReportPage -Title 'Summary' -Subtitle "Your IT at a glance for $PeriodLabel"))
        $blocks.Add((New-CippReportParagraph -Html ('<p>This report summarises the health and security of IT at <b>{0}</b> for {1}: how well accounts are protected, the state of your computers, what our monitoring picked up, and the support work we did. Each section ends with what it means for you; anything that needs a decision is collected under Recommendations at the end.</p>' -f (& $enc $Name), (& $enc $PeriodLabel))))
        if ($Summary) {
            $blocks.Add((New-CippReportInfoBox -Title 'A note from your IT team' -Content $Summary -Lines))
        }

        $Stats = [System.Collections.Generic.List[object]]::new()
        if ($M -and $M.SecureScore) { $Stats.Add(@{ value = "$($M.SecureScore.Percent)%"; label = 'Microsoft Secure Score'; colour = $(if ($M.SecureScore.Percent -lt 40) { $warnC }) }) }
        if ($M -and $M.Mfa -and $M.Mfa.Users -gt 0) {
            $MfaPct = [math]::Round(($M.Mfa.Protected / $M.Mfa.Users) * 100)
            $Stats.Add(@{ value = "$MfaPct%"; label = 'Accounts protected by MFA'; colour = $(if ($MfaPct -lt 100) { $warnC }) })
        }
        if ($A) {
            $Stats.Add(@{ value = "$($A.Devices.Active)"; label = 'Managed devices' })
            $Stats.Add(@{ value = "$($A.Tickets.Opened)"; label = 'Support requests' })
        }
        if ($Stats.Count -gt 0) { $blocks.Add((New-CippReportStatRow -Stats @($Stats))) }

        if ($Actions.Count -eq 0) {
            $blocks.Add((New-CippReportClearBox -Title 'Status: Good' -Content 'Nothing in this month''s checks needs action from you. We will keep monitoring and let you know if that changes.'))
        } else {
            $Level = if ($Actions.Count -ge 4) { 'Action needed' } else { 'Attention' }
            $Colour = if ($Actions.Count -ge 4) { $dangerC } else { $warnC }
            $blocks.Add((New-CippReportAlertBox -Title "Status: $Level" -Colour $Colour -Content "We found $(& $plural $Actions.Count 'item') that need attention. They are listed under Recommendations at the end of this report with what we suggest doing about each."))
        }
        }
        'm365-security' = {
        if ($M -and ($M.SecureScore -or $M.Mfa)) {
            $blocks.Add((New-CippReportPage -Title 'Microsoft 365 Security' -Subtitle 'How well your accounts and data are protected'))
            if ($M.SecureScore) {
                $S = $M.SecureScore
                $blocks.Add((New-CippReportHeading -Title 'Microsoft Secure Score'))
                $Compare = if ($null -ne $S.SimilarPercent) { " Organisations of a similar size average $($S.SimilarPercent)%." } else { '' }
                $Since = if ($S.ChangeSince) { " since $($S.ChangeSince.ToString('d MMMM'))" } else { '' }
                $Move = if ($S.Change -gt 0) { ", up $($S.Change) points$Since" } elseif ($S.Change -lt 0) { ", down $([math]::Abs($S.Change)) points$Since" } else { '' }
                $blocks.Add((New-CippReportParagraph -Text "Secure Score is Microsoft's own measure of how many of its recommended security settings are in place. It is a guide rather than a target: some recommendations do not suit every business. Your score is currently $($S.Current) of $($S.Max) ($($S.Percent)%)$Move.$Compare"))
                if (@($S.Trend).Count -gt 1) {
                    $blocks.Add((New-CippReportChart -Kind trend -Title 'Secure Score' -Max ([double]$S.Max) -Caption 'Recent daily scores' -Data @($S.Trend)))
                }
            }
            if ($M.Mfa) {
                $F = $M.Mfa
                $blocks.Add((New-CippReportHeading -Title 'Multi-factor authentication'))
                $blocks.Add((New-CippReportParagraph -Text 'Multi-factor authentication (a code or app approval as well as a password) blocks the large majority of account takeover attempts. Every active account should have it enforced.'))
                $blocks.Add((New-CippReportProgress -Title 'Accounts with MFA enforced' -Items @(@{ label = 'Protected'; value = [int]$F.Protected; max = [int]$F.Users; display = "$($F.Protected) of $($F.Users)"; colour = $(if ($F.Unprotected -gt 0) { $warnC } else { $okC }) })))
                if ($F.Unprotected -gt 0) {
                    $blocks.Add((New-CippReportNote -Text "$(& $plural $F.Unprotected 'account') can still sign in with just a password. See Recommendations."))
                }
            }
        }
        }
        'users-licences' = {
        if ($M) {
            $blocks.Add((New-CippReportPage -Title 'Users & Licences' -Subtitle 'Who has access, and what you are paying for'))
            $blocks.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($M.Users)"; label = 'Active user accounts' }
                        @{ value = "$($M.Licensed)"; label = 'Licensed users' }
                        @{ value = "$($M.Guests)"; label = 'Guest accounts' }
                        @{ value = "$($M.Unassigned)"; label = 'Spare licences'; colour = $(if ($M.Unassigned -gt 0) { $warnC }) }
                    )))
            if (@($M.Licences).Count -gt 0) {
                $blocks.Add((New-CippReportTable -Title 'Licences' -Limit 20 -Columns @(
                            @{ header = 'Licence'; key = 'name'; width = 3.2; bold = $true }
                            @{ header = 'Assigned'; key = 'used'; width = 1; align = 'right' }
                            @{ header = 'Owned'; key = 'total'; width = 1; align = 'right' }
                            @{ header = 'Spare'; key = 'available'; width = 1; align = 'right' }
                        ) -Rows @($M.Licences)))
                if ($M.Unassigned -gt 0) {
                    $blocks.Add((New-CippReportNote -Text 'Spare licences are paid for but not assigned to anyone. They may be held for new starters; if not, we can reduce them at the next renewal.'))
                }
            }
        }
        }
        'devices' = {
        if ($A -and $A.Devices.Total -gt 0) {
            $D = $A.Devices
            $blocks.Add((New-CippReportPage -Title 'Devices' -Subtitle 'The computers and servers we look after'))
            $blocks.Add((New-CippReportParagraph -Text "We monitor $(& $plural $D.Active 'device') for $Name. The checks below are the ones that most often lead to problems if left: an operating system that no longer gets security updates, a disk that is nearly full, and a machine that has not restarted to finish installing updates."))
            $blocks.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($D.Active)"; label = 'Active devices' }
                        @{ value = "$($D.Unsupported.Count)"; label = 'Unsupported OS'; colour = $(if ($D.Unsupported.Count -gt 0) { $dangerC }) }
                        @{ value = "$($D.LowDisk.Count)"; label = 'Low disk space'; colour = $(if ($D.LowDisk.Count -gt 0) { $warnC }) }
                        @{ value = "$($D.NotRebooted30.Count)"; label = 'Restart needed'; colour = $(if ($D.NotRebooted30.Count -gt 0) { $warnC }) }
                    )))
            if (@($D.ByOs).Count -gt 0) {
                $blocks.Add((New-CippReportChart -Kind donut -Title 'Operating systems' -CentreLabel 'devices' -Data @($D.ByOs)))
            }
            $Attention = @(
                @($D.Unsupported | ForEach-Object { @{ device = $_.name; issue = "$($_.os) - no longer supported"; user = $_.user; tone = 'fail' } })
                @($D.LowDisk | ForEach-Object { @{ device = $_.name; issue = "Disk $($_.freePct)% free"; user = $_.user; tone = 'warn' } })
                @($D.NotRebooted30 | ForEach-Object { @{ device = $_.name; issue = "Not restarted for $($_.daysSinceReboot) days"; user = $_.user; tone = 'warn' } })
            ) | Where-Object { $_ }
            if (@($Attention).Count -gt 0) {
                $blocks.Add((New-CippReportTable -Title 'Devices needing attention' -Limit 30 -EmptyText 'None' -Columns @(
                            @{ header = 'Device'; key = 'device'; width = 1.6; bold = $true }
                            @{ header = 'Issue'; key = 'issue'; width = 2.4; toneField = 'tone' }
                            @{ header = 'Last user'; key = 'user'; width = 1.6 }
                        ) -Rows @($Attention)))
            } else {
                $blocks.Add((New-CippReportClearBox -Title 'All devices healthy' -Content 'Every active device is on a supported operating system, has enough disk space and has restarted recently.'))
            }
        }
        }
        'monitoring' = {
        if ($A) {
            $blocks.Add((New-CippReportPage -Title 'Monitoring' -Subtitle "What our monitoring picked up in $PeriodLabel"))
            $blocks.Add((New-CippReportParagraph -Text 'Our monitoring watches your devices around the clock and raises an alert when something needs a look - a service stopping, a disk filling, a failed backup or update. Most alerts are dealt with before anyone notices; this is a summary of what came in.'))
            $blocks.Add((New-CippReportStatRow -Stats @(@{ value = "$($A.Alerts.Total)"; label = 'Alerts raised' })))
            if ($A.Alerts.Total -gt 0) {
                $blocks.Add((New-CippReportChart -Kind bar -Title 'Alerts by severity' -Data @($A.Alerts.BySeverity)))
                $blocks.Add((New-CippReportTable -Title 'Most common alerts' -Limit 6 -Columns @(
                            @{ header = 'Alert'; key = 'title'; width = 3.4 }
                            @{ header = 'Times'; key = 'count'; width = 0.8; align = 'right' }
                            @{ header = 'Devices'; key = 'devices'; width = 0.8; align = 'right' }
                        ) -Rows @($A.Alerts.TopTitles)))
            } else {
                $blocks.Add((New-CippReportClearBox -Title 'A quiet month' -Content 'No monitoring alerts were raised in this period.'))
            }
        }
        }
        'support' = {
        if ($A) {
            $T = $A.Tickets
            $blocks.Add((New-CippReportPage -Title 'Support' -Subtitle "Requests you raised in $PeriodLabel"))
            $blocks.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($T.Opened)"; label = 'Requests opened' }
                        @{ value = "$($T.Resolved)"; label = 'Resolved' }
                        @{ value = "$($T.OpenNow)"; label = 'Open now' }
                        @{ value = (& $hm $T.MinutesLogged); label = 'Time spent' }
                    )))
            if ($T.Opened -gt 0) {
                $Rows = @($T.List | ForEach-Object {
                        @{ number = $_.number; title = $_.title; created = $(if ($_.created) { $_.created.ToString('d MMM') } else { '' }); status = $_.status; time = (& $hm $_.minutes); tone = $(if ($_.status -in @('Closed', 'Resolved')) { 'pass' } else { 'warn' }) }
                    })
                $blocks.Add((New-CippReportTable -Title 'Requests' -Limit 40 -Columns @(
                            @{ header = 'Ref'; key = 'number'; width = 0.6 }
                            @{ header = 'Request'; key = 'title'; width = 3.2 }
                            @{ header = 'Opened'; key = 'created'; width = 0.9 }
                            @{ header = 'Status'; key = 'status'; width = 0.9; toneField = 'tone' }
                            @{ header = 'Time'; key = 'time'; width = 0.8; align = 'right' }
                        ) -Rows $Rows))
            } else {
                $blocks.Add((New-CippReportClearBox -Title 'No support requests' -Content 'You did not need to raise any support requests this month.'))
            }
        }
        }
        'recommendations' = {
        $blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What we suggest doing next'))
        if ($Actions.Count -gt 0) {
            $i = 0
            $Items = foreach ($F in $Actions) {
                $i++
                $Detail = if ($F.Items.Count -gt 0 -and $F.Items.Count -le 8) { "Affected: $(@($F.Items) -join ', ')." } elseif ($F.Items.Count -gt 8) { "Affected: $(@($F.Items | Select-Object -First 8) -join ', ') and $($F.Items.Count - 8) more." } else { '' }
                @{ marker = "$i."; label = $F.Customer; text = $Detail }
            }
            $blocks.Add((New-CippReportBullets -Items @($Items)))
            $blocks.Add((New-CippReportParagraph -Text 'We will be in touch about anything that needs your approval. If you would like to talk any of this through, just reply to this email or raise a support request.'))
        } else {
            $blocks.Add((New-CippReportClearBox -Title 'Nothing to action' -Content 'There are no recommendations this month.'))
        }
        }
    }

    # Assemble in the requested order. Built-in ids map to the builders above; anything else
    # (Report Builder templates, 'template:<GUID>') comes pre-resolved in -ExtraSections.
    $Order = @($Sections | Where-Object { $_ })
    if ($Order.Count -eq 0) { $Order = @($SectionBuilders.Keys) }
    foreach ($SectionId in $Order) {
        if ($SectionBuilders.Contains($SectionId)) {
            $null = & $SectionBuilders[$SectionId]
        } elseif ($ExtraSections -and $ExtraSections.ContainsKey($SectionId)) {
            $Extra = $ExtraSections[$SectionId]
            if (@($Extra.Blocks).Count -gt 0) {
                $blocks.Add((New-CippReportPage -Title $Extra.Title -Subtitle $(if ($Extra.Subtitle) { $Extra.Subtitle } else { $PeriodLabel })))
                foreach ($B in @($Extra.Blocks)) { $blocks.Add($B) }
            }
        }
    }

    $Meta = @()
    if ($A) { $Meta += (& $plural $A.Devices.Active 'device') }
    if ($M) { $Meta += (& $plural $M.Users 'user') }
    $Meta += $(if ($Actions.Count -gt 0) { & $plural $Actions.Count 'recommendation' } else { 'no actions needed' })

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Monthly IT Report'
            covertenant        = $Name
            coversubtitle      = "The health and security of IT at $Name for $PeriodLabel."
            covermeta          = ($Meta -join " $([char]0x00B7) ")
            covermetanote      = $PeriodLabel
            coverfooternote    = "Confidential $([char]0x2014) prepared for $Name"
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel        = "$Name $([char]0x2014) $PeriodLabel"
        }
    }
}
