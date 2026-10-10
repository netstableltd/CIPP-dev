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
        summary, devices, updates, device-health, monitoring, support, purchases, m365-security,
        users-licences, email, recommendations (the default order when empty), plus m365-baseline
        (opt-in: the CIPP Executive Summary).

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
        [hashtable]$ExtraSections,
        # Pre-built Microsoft 365 baseline (Get-CIPPReportBaselineSection), used by the 'm365-baseline' section.
        [hashtable]$Baseline
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
    $Planned = @($Findings | Where-Object { $_.Customer -and $_.Severity -eq 'Info' })

    $blocks = [System.Collections.Generic.List[object]]::new()

    $SectionBuilders = [ordered]@{
        'summary' = {
        $blocks.Add((New-CippReportPage -Title 'Summary' -Subtitle "Your IT at a glance for $PeriodLabel"))
        $blocks.Add((New-CippReportParagraph -Html ('<p>This report summarises the health and security of IT at <b>{0}</b> for {1}: the state of your computers and their updates, what our monitoring picked up, the support work we did, what you bought, and how well your Microsoft 365 accounts and email are protected. Each section ends with what it means for you; anything that needs a decision is collected under Recommendations at the end.</p>' -f (& $enc $Name), (& $enc $PeriodLabel))))
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
            $PlanText = if ($Planned.Count -gt 0) { " and $(& $plural $Planned.Count 'thing') to plan for" } else { '' }
            $blocks.Add((New-CippReportAlertBox -Title "Status: $Level" -Colour $Colour -Content "We found $(& $plural $Actions.Count 'item') that need attention$PlanText. They are listed under Recommendations at the end of this report with what we suggest doing about each."))
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
                    $blocks.Add((New-CippReportChart -Kind trend -Title 'Secure Score' -Max ([double]$S.Max) -Caption 'Daily scores, last two weeks' -Data @($S.Trend)))
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
                if ($F.ViaSecurityDefaults -gt 0) {
                    $blocks.Add((New-CippReportNote -Text "$(if ($F.ViaSecurityDefaults -eq $F.Protected) { 'All of these are' } else { "$($F.ViaSecurityDefaults) of these are" }) covered by Microsoft's Security Defaults, which make everyone set up MFA and ask for it when a sign-in looks risky. Conditional Access (included in Microsoft 365 Business Premium) gives finer control, such as always requiring MFA away from the office."))
                }
            }
        }
        }
        'users-licences' = {
        if ($M) {
            $blocks.Add((New-CippReportPage -Title 'Users & Licences' -Subtitle 'Who has access, and what you are paying for'))
            $blocks.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($M.Users)"; label = 'User accounts' }
                        @{ value = "$($M.Licensed)"; label = 'With a paid licence' }
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
            $blocks.Add((New-CippReportPage -Title 'Your Computers' -Subtitle 'Every computer we look after, and how it is doing'))
            $NeedAttention = @($D.List | Where-Object { $_.health -eq 'Needs attention' -and ($null -eq $_.daysSinceSeen -or $_.daysSinceSeen -lt 30) }).Count
            $blocks.Add((New-CippReportParagraph -Text "We look after $(& $plural $D.Active 'computer') for $Name. Each one is checked for Windows updates, whether its version of Windows still gets security fixes, disk space, restarts, recurring performance alerts and whether its hardware is up to the job. The table shows where each computer stands today; the next pages explain the detail."))
            $blocks.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($D.Active)"; label = 'Computers' }
                        @{ value = "$($D.Healthy)"; label = 'In good shape'; colour = $okC }
                        @{ value = "$NeedAttention"; label = 'Need attention'; colour = $(if ($NeedAttention -gt 0) { $dangerC }) }
                        @{ value = "$($D.UpToDate)"; label = 'Fully updated' }
                    )))
            $LastSeenText = {
                param($Row)
                if ($Row.online) { 'Online now' }
                elseif ($null -eq $Row.daysSinceSeen) { '' }
                elseif ($Row.daysSinceSeen -eq 0) { 'Today' }
                elseif ($Row.daysSinceSeen -eq 1) { 'Yesterday' }
                else { "$($Row.daysSinceSeen) days ago" }
            }
            $Rows = @($D.List | ForEach-Object {
                    $Spec = (@(($_.cpu -replace ' \(c\. \d{4}\)', '' -replace '^Intel Core ', '' -replace '^AMD ', ''), $(if ($_.memoryGB) { "$($_.memoryGB) GB" })) | Where-Object { $_ }) -join ', '
                    @{
                        name   = $_.name
                        user   = $_.user
                        windows = $_.version
                        spec   = $Spec
                        seen   = (& $LastSeenText $_)
                        status = $_.health
                        tone   = $(switch ($_.health) { 'Good' { 'pass' } 'Check' { 'warn' } 'Needs attention' { 'fail' } default { '' } })
                    }
                })
            $blocks.Add((New-CippReportTable -Title 'Computers' -Limit 200 -Columns @(
                        @{ header = 'Computer'; key = 'name'; width = 1.5; bold = $true }
                        @{ header = 'User'; key = 'user'; width = 1.3 }
                        @{ header = 'Windows'; key = 'windows'; width = 1.3 }
                        @{ header = 'Hardware'; key = 'spec'; width = 1.5 }
                        @{ header = 'Last seen'; key = 'seen'; width = 1 }
                        @{ header = 'Status'; key = 'status'; width = 1.1; toneField = 'tone' }
                    ) -Rows $Rows))
            $Why = @($D.List | Where-Object { $_.health -in @('Needs attention', 'Check') -and $_.healthNotes } | ForEach-Object {
                    $Text = "$($_.healthNotes)"; $Text = $Text.Substring(0, 1).ToUpper() + $Text.Substring(1)
                    @{ name = $_.name; why = $Text; tone = $(if ($_.health -eq 'Needs attention') { 'fail' } else { 'warn' }) }
                })
            if ($Why.Count -gt 0) {
                $blocks.Add((New-CippReportTable -Title 'Why a computer needs attention' -Limit 100 -Columns @(
                            @{ header = 'Computer'; key = 'name'; width = 1.4; bold = $true }
                            @{ header = 'What we found'; key = 'why'; width = 4.6; toneField = 'tone' }
                        ) -Rows $Why))
            } else {
                $blocks.Add((New-CippReportClearBox -Title 'All computers in good shape' -Content 'Every computer is up to date, on a supported version of Windows, has enough disk space and has restarted recently.'))
            }
        }
        }
        'updates' = {
        if ($A -and $A.Devices.Total -gt 0) {
            $D = $A.Devices
            $Act = @($D.List | Where-Object { $null -eq $_.daysSinceSeen -or $_.daysSinceSeen -lt 30 })
            $blocks.Add((New-CippReportPage -Title 'Updates' -Subtitle 'Windows and Microsoft software updates, and how long each version of Windows is supported'))
            $blocks.Add((New-CippReportParagraph -Text 'Microsoft releases security fixes every month for Windows and its other software (.NET, Office, drivers), and each version of Windows only receives them for a set time. Our monitoring checks each computer for the updates it still needs. A computer showing updates waiting usually needs a restart, or was switched off when updates ran. A computer on a version of Windows that no longer receives fixes stays exposed to every new vulnerability found after that date.'))
            $Unsupported = @($Act | Where-Object { $_.support -eq 'Unsupported' })
            $Ending = @($Act | Where-Object { $_.support -eq 'Ending soon' })
            $Restart = @($Act | Where-Object { $_.daysSinceReboot -gt 30 })
            $Failing = @($Act | Where-Object { [int]$_.securityFailed -gt 0 })
            $blocks.Add((New-CippReportStatRow -Stats @(
                        @{ value = "$($D.UpToDate)"; label = 'Up to date'; colour = $okC }
                        @{ value = "$(@($D.UpdatesBehind).Count)"; label = 'Need security updates'; colour = $(if (@($D.UpdatesBehind).Count -gt 0) { $dangerC }) }
                        @{ value = "$($Failing.Count)"; label = 'Updates failing'; colour = $(if ($Failing.Count -gt 0) { $warnC }) }
                        @{ value = "$($Unsupported.Count + $Ending.Count)"; label = 'Windows support ended or ending'; colour = $(if ($Unsupported.Count -gt 0) { $dangerC } elseif ($Ending.Count -gt 0) { $warnC }) }
                    )))
            $FormatEnd = { param($Iso) if ($Iso) { try { ([datetime]::ParseExact($Iso, 'yyyy-MM-dd', [cultureinfo]::InvariantCulture)).ToString('d MMM yyyy') } catch { $Iso } } else { '' } }
            $Rows = @($Act | Sort-Object { switch ($_.support) { 'Unsupported' { 0 } 'Ending soon' { 1 } default { 2 } } }, { switch ($_.updateStatus) { 'Behind' { 0 } 'Failing' { 1 } default { 2 } } }, name | ForEach-Object {
                    $Dev = $_
                    $Upd = switch ($Dev.updateStatus) {
                        'Up to date' { 'Up to date' }
                        'Behind' { if ($null -ne $Dev.securityWaiting) { "$($Dev.securityWaiting) security update$(if ([int]$Dev.securityWaiting -ne 1) { 's' }) waiting" } else { 'Behind' } }
                        'Failing' { 'Security update failing' }
                        default { 'Not known' }
                    }
                    if ($Dev.daysSinceReboot -gt 30) { $Upd = "$Upd - restart needed" }
                    if ($Dev.patchScanDate -and ($Data.GeneratedAt - $Dev.patchScanDate).TotalDays -gt 7) { $Upd = "$Upd (last checked $($Dev.patchScanDate.ToString('d MMM')))" }
                    $Last = if ($Dev.lastSecurityUpdate) { & $FormatEnd $Dev.lastSecurityUpdate } else { '' }
                    @{
                        name    = $Dev.name
                        windows = $Dev.version
                        until   = $(if ($Dev.support -eq 'Unsupported') { 'Ended' } elseif ($Dev.supportEnds) { & $FormatEnd $Dev.supportEnds } elseif ($Dev.support -eq 'Supported') { 'Latest version' } else { '' })
                        ut      = $(switch ($Dev.support) { 'Unsupported' { 'fail' } 'Ending soon' { 'warn' } 'Supported' { 'pass' } default { '' } })
                        last    = $Last
                        update  = $Upd
                        tone    = $(if ($Dev.updateStatus -in @('Behind', 'Failing') -or $Dev.daysSinceReboot -gt 30) { 'fail' } elseif ($Dev.updateStatus -eq 'Up to date') { 'pass' } else { '' })
                    }
                })
            $blocks.Add((New-CippReportTable -Title 'Update status' -Limit 200 -Columns @(
                        @{ header = 'Computer'; key = 'name'; width = 1.4; bold = $true }
                        @{ header = 'Windows'; key = 'windows'; width = 1.3 }
                        @{ header = 'Last security update'; key = 'last'; width = 1.1 }
                        @{ header = 'Updates'; key = 'update'; width = 1.7; toneField = 'tone' }
                        @{ header = 'Security fixes until'; key = 'until'; width = 1.2; toneField = 'ut' }
                    ) -Rows $Rows))
            $Waiting = @($Act | Where-Object { $_.updatesWaiting -or $_.updatesFailing -or $_.driversWaiting })
            if ($Waiting.Count -gt 0) {
                $AllRows = @(foreach ($Dev in $Waiting) {
                        foreach ($U in @("$($Dev.updatesFailing)" -split '; ' | Where-Object { $_ })) { @{ order = 0; name = $Dev.name; update = $U; state = 'Failed'; tone = 'fail' } }
                        foreach ($U in @("$($Dev.updatesWaiting)" -split '; ' | Where-Object { $_ })) { $Sec = $U -match 'Security|Cumulative'; @{ order = $(if ($Sec) { 1 } else { 2 }); name = $Dev.name; update = $U; state = 'Waiting'; tone = $(if ($Sec) { 'fail' } else { 'warn' }) } }
                        foreach ($U in @("$($Dev.driversWaiting)" -split '; ' | Where-Object { $_ })) { @{ order = 3; name = $Dev.name; update = $U; state = 'Optional driver'; tone = '' } }
                        foreach ($U in @("$($Dev.driversFailing)" -split '; ' | Where-Object { $_ })) { @{ order = 3; name = $Dev.name; update = $U; state = 'Optional driver (failed)'; tone = '' } }
                    })
                $WRows = @($AllRows | Sort-Object { $_.order }, { $_.name })
                $blocks.Add((New-CippReportTable -Title 'Updates still to install' -Limit 60 -Columns @(
                            @{ header = 'Computer'; key = 'name'; width = 1.4; bold = $true }
                            @{ header = 'Update'; key = 'update'; width = 4 }
                            @{ header = 'State'; key = 'state'; width = 1; toneField = 'tone' }
                        ) -Rows $WRows))
            }
            if ($Ending.Count -gt 0) {
                $Ends = @($Ending | ForEach-Object { & $FormatEnd $_.supportEnds } | Sort-Object -Unique) -join ', '
                $blocks.Add((New-CippReportAlertBox -Title 'Windows support ending soon' -Colour $warnC -Content "$(& $plural $Ending.Count 'computer') $(if ($Ending.Count -eq 1) { 'is' } else { 'are' }) on a version of Windows that stops receiving security fixes on $Ends. Moving to the current version is a free update that we will schedule with the users."))
            }
            if ($Unsupported.Count -gt 0) {
                $blocks.Add((New-CippReportAlertBox -Title 'No longer receiving security fixes' -Colour $dangerC -Content "$(& $plural $Unsupported.Count 'computer') $(if ($Unsupported.Count -eq 1) { 'runs' } else { 'run' }) a version of Windows Microsoft no longer supports: $(@($Unsupported | ForEach-Object { "$($_.name) ($($_.version))" }) -join ', '). These should be upgraded or replaced as a priority."))
            }
            if (@($D.UpdatesBehind).Count -eq 0 -and $Failing.Count -eq 0 -and $Ending.Count -eq 0 -and $Unsupported.Count -eq 0 -and $Restart.Count -eq 0) {
                $blocks.Add((New-CippReportClearBox -Title 'Fully up to date' -Content 'Every computer has this month''s updates and is on a supported version of Windows.'))
            }
            $Scanned = [int]$D.PatchScanned
            $blocks.Add((New-CippReportNote -Text $(if ($Scanned -ge $Act.Count) { 'From each computer''s latest update scan in our monitoring. Driver updates are optional and listed for completeness. Antivirus definition updates are not counted: they install automatically several times a day.' } else { "From each computer's latest update scan in our monitoring ($Scanned of $($Act.Count) computers; the others are compared with the Windows build of the computers we manage). Antivirus definition updates are not counted." })))
        }
        }
        'device-health' = {
        if ($A -and $A.Devices.Total -gt 0) {
            $D = $A.Devices
            $blocks.Add((New-CippReportPage -Title 'Computer Health' -Subtitle 'Memory, storage and hardware'))
            $blocks.Add((New-CippReportParagraph -Text 'This page looks for computers that are struggling or due an upgrade: ones that run out of memory during the working day, drives that are filling up, and hardware below our minimum standard of a processor with at least four cores that can run Windows 11.'))
            $Any = $false
            $Mp = @($D.MemoryPressure)
            if ($Mp.Count -gt 0) {
                $Any = $true
                $blocks.Add((New-CippReportTable -Title 'Running out of memory during the working day' -Limit 30 -Columns @(
                            @{ header = 'Computer'; key = 'name'; width = 1.5; bold = $true }
                            @{ header = 'Days over 90%'; key = 'days'; width = 1; align = 'right'; toneField = 'tone' }
                            @{ header = 'Highest'; key = 'peak'; width = 0.8; align = 'right' }
                            @{ header = 'Memory fitted'; key = 'ram'; width = 1; align = 'right' }
                            @{ header = 'Using most memory'; key = 'top'; width = 1.6 }
                        ) -Rows @($Mp | ForEach-Object { @{ name = $_.name; days = "$($_.memoryDays)"; tone = 'warn'; peak = "$($_.memoryPeak)%"; ram = $(if ($_.memoryGB) { "$($_.memoryGB) GB" }); top = $_.memoryTopProcess } })))
                $blocks.Add((New-CippReportNote -Text "Days in $PeriodLabel when memory use went over 90% between 8am and 6pm on a weekday. Adding memory is usually the cheapest way to speed these computers up."))
            }
            $Full = @($D.StorageOver75)
            if ($Full.Count -gt 0) {
                $Any = $true
                $SRows = @(foreach ($Dev in $Full) {
                        foreach ($Drive in @("$($Dev.drivesOver75)" -split '; ' | Where-Object { $_ })) {
                            $Pct = [int](($Drive -split ' ')[-1] -replace '%', '')
                            @{ name = $Dev.name; drive = ($Drive -split ' ')[0]; full = "$Pct% full"; tone = $(if ($Pct -gt 90) { 'fail' } else { 'warn' }) }
                        }
                    })
                $blocks.Add((New-CippReportTable -Title 'Drives more than three-quarters full' -Limit 40 -Columns @(
                            @{ header = 'Computer'; key = 'name'; width = 1.6; bold = $true }
                            @{ header = 'Drive'; key = 'drive'; width = 0.8 }
                            @{ header = 'Used'; key = 'full'; width = 1; align = 'right'; toneField = 'tone' }
                        ) -Rows $SRows))
                $blocks.Add((New-CippReportNote -Text 'Once a drive is more than three-quarters full it is time to delete or archive old files, or fit a bigger drive. Over 90% full, Windows updates and everyday work start to fail.'))
            }
            $Bb = @($D.BelowBaseline)
            if ($Bb.Count -gt 0) {
                $Any = $true
                $blocks.Add((New-CippReportTable -Title 'Below our hardware baseline' -Limit 50 -Columns @(
                            @{ header = 'Computer'; key = 'name'; width = 1.4; bold = $true }
                            @{ header = 'Processor'; key = 'cpu'; width = 2.2 }
                            @{ header = 'Cores'; key = 'cores'; width = 0.6; align = 'right' }
                            @{ header = 'Why'; key = 'why'; width = 2; toneField = 'tone' }
                        ) -Rows @($Bb | ForEach-Object { @{ name = $_.name; cpu = $_.cpu; cores = "$($_.cores)"; why = $_.hardwareNotes; tone = 'fail' } })))
            }
            if (@($D.HomeEdition).Count -gt 0) {
                $Any = $true
                $blocks.Add((New-CippReportInfoBox -Title 'Windows Home edition' -Tone warn -Content "$(@($D.HomeEdition | ForEach-Object { $_.name }) -join ', ') $(if (@($D.HomeEdition).Count -eq 1) { 'runs' } else { 'run' }) Windows Home, which is meant for personal use: it cannot be managed centrally or have its disk encryption managed like your other computers. Upgrading to Windows Pro is a licence change, not a reinstall."))
            }
            if (@($D.AlertsByDevice).Count -gt 0) {
                $Any = $true
                $blocks.Add((New-CippReportTable -Title 'Monitoring alerts this month by computer' -Limit 15 -Columns @(
                            @{ header = 'Computer'; key = 'name'; width = 1.6; bold = $true }
                            @{ header = 'Alerts'; key = 'alerts'; width = 1; align = 'right' }
                        ) -Rows @($D.AlertsByDevice | ForEach-Object { @{ name = $_.name; alerts = "$($_.alertsInPeriod)" } })))
            }
            if (-not $Any) {
                $blocks.Add((New-CippReportClearBox -Title 'No health concerns' -Content 'Every computer meets our hardware baseline, no drive is more than three-quarters full, and no computer ran out of memory during the working day.'))
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
                $blocks.Add((New-CippReportClearBox -Title 'No alerts' -Content 'No monitoring alerts were raised in this period.'))
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
                if (@($T.ByRequester).Count -gt 1) {
                    $blocks.Add((New-CippReportChart -Kind bar -Title 'Requests by person' -Data @($T.ByRequester)))
                }
                $Rows = @($T.List | ForEach-Object {
                        @{ number = $_.number; title = $_.title; who = $_.requester; created = $(if ($_.created) { $_.created.ToString('d MMM') } else { '' }); status = $_.status; time = (& $hm $_.minutes); tone = $(if ($_.status -in @('Closed', 'Resolved')) { 'pass' } else { 'warn' }) }
                    })
                $blocks.Add((New-CippReportTable -Title 'Requests' -Limit 60 -Columns @(
                            @{ header = 'Ref'; key = 'number'; width = 0.6 }
                            @{ header = 'Request'; key = 'title'; width = 2.6 }
                            @{ header = 'From'; key = 'who'; width = 0.9 }
                            @{ header = 'Opened'; key = 'created'; width = 0.9 }
                            @{ header = 'Status'; key = 'status'; width = 0.9; toneField = 'tone' }
                            @{ header = 'Time'; key = 'time'; width = 0.8; align = 'right' }
                        ) -Rows $Rows))
            } else {
                $blocks.Add((New-CippReportClearBox -Title 'No support requests' -Content 'You did not need to raise any support requests this month.'))
            }
        }
        }
        'purchases' = {
        if ($A -and $A.Purchases) {
            $P = $A.Purchases
            $Cur = if ($P.Currency) { $P.Currency } else { [char]0x00A3 }
            $Money = { param($v) '{0}{1:N2}' -f $Cur, [double]$v }
            $blocks.Add((New-CippReportPage -Title 'Purchases' -Subtitle 'Equipment and services bought through us'))
            if (-not $P.Available) {
                $blocks.Add((New-CippReportClearBox -Title 'No purchases' -Content 'There were no equipment or service purchases in the last twelve months.'))
            } else {
                $blocks.Add((New-CippReportStatRow -Stats @(
                            @{ value = "$(@($P.Period).Count)"; label = "Items in $PeriodLabel" }
                            @{ value = (& $Money $P.PeriodTotal); label = 'Spent this month' }
                            @{ value = "$(@($P.Year).Count)"; label = 'Items in 12 months' }
                            @{ value = (& $Money $P.YearTotal); label = 'Spent in 12 months' }
                        )))
                $Row = { param($x) @{ date = $x.date.ToString('d MMM yyyy'); item = $x.item; details = $x.details; qty = $(if ($x.quantity -eq [math]::Floor($x.quantity)) { "$([int]$x.quantity)" } else { "$($x.quantity)" }); total = (& $Money $x.total) } }
                $Cols = @(
                    @{ header = 'Date'; key = 'date'; width = 1 }
                    @{ header = 'Item'; key = 'item'; width = 2.6; bold = $true }
                    @{ header = 'Details'; key = 'details'; width = 1.8 }
                    @{ header = 'Qty'; key = 'qty'; width = 0.5; align = 'right' }
                    @{ header = 'Total'; key = 'total'; width = 0.9; align = 'right' }
                )
                if (@($P.Period).Count -gt 0) {
                    $blocks.Add((New-CippReportTable -Title "Bought in $PeriodLabel" -Limit 50 -Columns $Cols -Rows @($P.Period | ForEach-Object { & $Row $_ })))
                }
                $Earlier = @($P.Year | Where-Object { $_.date -lt $Data.Period.Start })
                if ($Earlier.Count -gt 0) {
                    $blocks.Add((New-CippReportTable -Title 'Earlier in the last 12 months' -Limit 100 -Columns $Cols -Rows @($Earlier | ForEach-Object { & $Row $_ })))
                }
                $blocks.Add((New-CippReportNote -Text 'Taken from your invoices, as invoiced.'))
            }
        }
        }
        'email' = {
        if ($M -and (@($M.Mailboxes).Count -gt 0 -or @($M.Domains).Count -gt 0)) {
            $blocks.Add((New-CippReportPage -Title 'Email & Domains' -Subtitle 'Mailbox space and protection against fake email'))
            if (@($M.Mailboxes).Count -gt 0) {
                $blocks.Add((New-CippReportHeading -Title 'Mailbox space'))
                $blocks.Add((New-CippReportParagraph -Text 'Each mailbox has a size limit; when it is reached the mailbox stops sending email. The fullest mailboxes are shown below. Turning on the free online archive moves older email out of the way without deleting it.'))
                $blocks.Add((New-CippReportProgress -Title 'Fullest mailboxes' -Items @($M.Mailboxes | Select-Object -First 8 | ForEach-Object {
                                @{ label = $_.name; value = [double]$_.usedGB; max = [double]$_.quotaGB; display = "$($_.usedGB) of $($_.quotaGB) GB ($($_.percent)%)"; colour = $(if ($_.percent -ge 90) { $dangerC } elseif ($_.percent -ge 80) { $warnC } else { $okC }) }
                            })))
            }
            if (@($M.Domains).Count -gt 0) {
                $blocks.Add((New-CippReportHeading -Title 'Email security for your domains'))
                $blocks.Add((New-CippReportParagraph -Text 'Three settings stop criminals sending email that pretends to come from you: SPF (which servers may send for the domain), DKIM (a signature on each email) and DMARC (what to do with email that fails those checks). Domains you own but do not use for email need SPF and DMARC too, set to reject everything, or they can be used for fake email.'))
                $YesNo = { param($b) if ($b) { 'Yes' } else { 'No' } }
                $blocks.Add((New-CippReportTable -Title 'Domains' -Limit 30 -Columns @(
                            @{ header = 'Domain'; key = 'domain'; width = 1.8; bold = $true }
                            @{ header = 'Used for email'; key = 'used'; width = 1 }
                            @{ header = 'SPF'; key = 'spf'; width = 0.6; toneField = 'spfTone' }
                            @{ header = 'DKIM'; key = 'dkim'; width = 0.6; toneField = 'dkimTone' }
                            @{ header = 'DMARC'; key = 'dmarc'; width = 0.9; toneField = 'dmarcTone' }
                            @{ header = 'Verdict'; key = 'verdict'; width = 1.3; toneField = 'tone' }
                        ) -Rows @($M.Domains | ForEach-Object {
                                @{
                                    domain = $_.domain; used = (& $YesNo $_.inUse)
                                    spf = (& $YesNo $_.spf); spfTone = $(if ($_.spf) { 'pass' } else { 'fail' })
                                    dkim = $(if ($_.inUse) { & $YesNo $_.dkim } else { 'n/a' }); dkimTone = $(if (-not $_.inUse) { '' } elseif ($_.dkim) { 'pass' } else { 'fail' })
                                    dmarc = $_.dmarc; dmarcTone = $(if ($_.dmarc -in @('Reject', 'Quarantine')) { 'pass' } elseif ($_.dmarc -eq 'None') { 'fail' } else { 'warn' })
                                    verdict = $_.verdict; tone = $(if ($_.verdict -eq 'Protected') { 'pass' } else { 'fail' })
                                }
                            })))
            }
        }
        }
        'breaches' = {
        $Br = $Data.Breaches
        if ($Br) {
            $blocks.Add((New-CippReportPage -Title 'Data Breaches' -Subtitle 'Your email addresses in known breaches of other websites'))
            $blocks.Add((New-CippReportParagraph -Text 'When a website or service is hacked, the email addresses (and often passwords) of its users are published. We check every email domain you own against the known breaches each month. A match does not mean your Microsoft 365 was breached: it means someone signed up to that website with a work address. The risk is a reused password, so anyone listed should make sure they use a different password for work, and multi-factor authentication protects the account either way.'))
            if ($Br.Source -eq 'None') {
                $blocks.Add((New-CippReportInfoBox -Title 'Breach check unavailable' -Tone warn -Content 'The breach check could not run this month. It will run again with next month''s report.'))
            } elseif ($Br.Total -eq 0) {
                $blocks.Add((New-CippReportClearBox -Title 'No addresses found' -Content 'None of your email addresses appear in the known data breaches.'))
            } else {
                $blocks.Add((New-CippReportStatRow -Stats @(
                            @{ value = "$($Br.Total)"; label = 'Addresses found' }
                            @{ value = "$(@($Br.People).Count)"; label = 'People affected'; colour = $(if (@($Br.People).Count -gt 0) { $warnC }) }
                            @{ value = "$($Br.PeopleWithPasswords)"; label = 'Passwords exposed'; colour = $(if ($Br.PeopleWithPasswords -gt 0) { $dangerC }) }
                        )))
                $Rows = @($Br.Accounts | ForEach-Object {
                        $Acc = $_
                        $List = @($_.breaches)
                        $Shown = @($List | Select-Object -First 3 | ForEach-Object { if ($_.date -and $_.date.Length -ge 4) { "$($_.title) ($($_.date.Substring(0, 4)))" } else { $_.title } })
                        $Classes = @(@($List | ForEach-Object { @($_.classes) }) + $(if ($_.passwords) { 'Passwords' }) | Where-Object { $_ -in @('Passwords', 'Email addresses', 'Phone numbers', 'Physical addresses', 'Dates of birth', 'Names', 'IP addresses', 'Credit cards', 'Bank account numbers') } | Sort-Object -Unique)
                        @{
                            email    = $_.email
                            breaches = ($Shown -join ', ') + $(if ($List.Count -gt 3) { " and $($List.Count - 3) more" } else { '' })
                            exposed  = $(if ($Classes.Count -gt 0) { $Classes -join ', ' } else { 'Email address' })
                            tone     = $(if ($_.passwords) { 'fail' } else { 'warn' })
                            account  = $(switch ($Acc.kind) { 'Person' { if ($Acc.alias) { "Alias of $($Acc.owner)" } else { 'In use' } } 'Shared mailbox' { 'Shared mailbox' } 'Disabled account' { 'Disabled account' } 'Not in use' { 'No longer in use' } default { '' } })
                        }
                    })
                $blocks.Add((New-CippReportTable -Title 'Addresses found in breaches' -Limit 100 -Columns @(
                            @{ header = 'Email address'; key = 'email'; width = 1.8; bold = $true }
                            @{ header = 'Breaches'; key = 'breaches'; width = 2.2 }
                            @{ header = 'What was exposed'; key = 'exposed'; width = 1.6; toneField = 'tone' }
                            @{ header = 'Account'; key = 'account'; width = 0.9 }
                        ) -Rows $Rows))
            }
            $When = if ($Br.CheckedAt) { ([datetime]$Br.CheckedAt).ToString('d MMMM yyyy') } else { '' }
            $blocks.Add((New-CippReportNote -Text "Checked $When using CIPP's breach lookup, with breach details from Have I Been Pwned (haveibeenpwned.com)."))
        }
        }
        'm365-baseline' = {
        if ($Baseline -and @($Baseline.Blocks).Count -gt 0) {
            foreach ($B in @($Baseline.Blocks)) { $blocks.Add($B) }
        }
        }
        'recommendations' = {
        $blocks.Add((New-CippReportPage -Title 'Recommendations' -Subtitle 'What we suggest doing next'))
        $Plan = @($Findings | Where-Object { $_.Customer -and $_.Severity -eq 'Info' })
        if ($Actions.Count -gt 0 -and $Plan.Count -gt 0) { $blocks.Add((New-CippReportHeading -Title 'To do now')) }
        if ($Actions.Count -gt 0) {
            $i = 0
            $Items = foreach ($F in $Actions) {
                $i++
                $Shown = @(if ($F.PSObject.Properties.Name -contains 'CustomerItems') { $F.CustomerItems } else { $F.Items })
                $Detail = if ($Shown.Count -gt 0 -and $Shown.Count -le 8) { "Affected: $($Shown -join ', ')." } elseif ($Shown.Count -gt 8) { "Affected: $(@($Shown | Select-Object -First 8) -join ', ') and $($Shown.Count - 8) more." } else { '' }
                @{ marker = "$i."; label = $F.Customer; text = $Detail }
            }
            $blocks.Add((New-CippReportBullets -Items @($Items)))
        }
        if ($Plan.Count -gt 0) {
            $blocks.Add((New-CippReportHeading -Title 'To plan for'))
            $i = 0
            $PlanItems = foreach ($F in $Plan) {
                $i++
                $Shown = @(if ($F.PSObject.Properties.Name -contains 'CustomerItems') { $F.CustomerItems } else { $F.Items })
                $Detail = if ($Shown.Count -gt 0 -and $Shown.Count -le 8) { "Affected: $($Shown -join ', ')." } elseif ($Shown.Count -gt 8) { "Affected: $(@($Shown | Select-Object -First 8) -join ', ') and $($Shown.Count - 8) more." } else { '' }
                @{ marker = "$i."; label = $F.Customer; text = $Detail }
            }
            $blocks.Add((New-CippReportBullets -Items @($PlanItems)))
        }
        if ($Actions.Count -gt 0 -or $Plan.Count -gt 0) {
            $blocks.Add((New-CippReportParagraph -Text 'We will be in touch about anything that needs your approval. If you would like to talk any of this through, just reply to this email or raise a support request.'))
        } else {
            $blocks.Add((New-CippReportClearBox -Title 'Nothing to action' -Content 'There are no recommendations this month.'))
        }
        }
    }

    # Assemble in the requested order. Built-in ids map to the builders above; anything else
    # (Report Builder templates, 'template:<GUID>') comes pre-resolved in -ExtraSections.
    $Order = @($Sections | Where-Object { $_ })
    if ($Order.Count -eq 0) { $Order = @('summary', 'devices', 'updates', 'device-health', 'monitoring', 'support', 'purchases', 'm365-security', 'users-licences', 'email', 'breaches', 'recommendations') }
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
    $Meta += $(if (($Actions.Count + $Planned.Count) -gt 0) { & $plural ($Actions.Count + $Planned.Count) 'recommendation' } else { 'no actions needed' })

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
