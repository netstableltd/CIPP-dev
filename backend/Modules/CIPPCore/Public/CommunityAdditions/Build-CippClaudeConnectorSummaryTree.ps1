function Build-CippClaudeConnectorSummaryTree {
    <#
    .SYNOPSIS
        Composes the end-of-setup summary PDF for Claude for Microsoft 365 as a component tree for
        ConvertTo-CippReportPdf.

    .DESCRIPTION
        What was set up for the customer, read from the tenant (Get-CIPPClaudeConnectorStatus): who can use
        Claude and at what level, what Claude can read, the safeguards in place, anything not finished,
        and what the customer does next. The level wording comes from Config/ClaudeConnectorAccess.json.

    .PARAMETER TenantName
        Customer name.

    .PARAMETER Status
        Output of Get-CIPPClaudeConnectorStatus.

    .PARAMETER ContactName
        Optional: who the summary is addressed to.

    .PARAMETER PreparedBy
        Optional: who it is from.

    .PARAMETER GeneratedOn
        The date shown in the text ("as of ...").

    .OUTPUTS
        @{ Blocks; Variables }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantName,
        [Parameter(Mandatory)]$Status,
        [string]$ContactName,
        [string]$PreparedBy,
        [string]$GeneratedOn
    )

    $Config = Get-CIPPClaudeConnectorAccessConfig
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $LevelOf = { param($Id) $Config.levels | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
    $LevelName = { param($L) if ($L) { "Level $($L.number): $($L.name)" } else { 'Custom permissions' } }
    $S = $Status
    $Apps = @($S.Apps)
    $Server = $Apps | Where-Object { $_.Key -eq 'Server' } | Select-Object -First 1
    $Access = $S.Access
    $Everyone = & $LevelOf $Access.Level
    $blocks = [System.Collections.Generic.List[object]]::new()

    # ------------------------------------------------------------------ who
    # People who can use Claude: the access group's members when the group is assigned, else the people
    # assigned to the app directly. Each has their own level if they have one, else everyone's.
    $Own = @{}
    foreach ($P in @($Access.People)) { $Own["$($P.UserId)"] = $P }
    $People = [System.Collections.Generic.List[object]]::new()
    if ($S.AssignedByGroup -and $S.Group.Exists) {
        foreach ($M in @($S.Group.Members)) { $People.Add([pscustomobject]@{ Id = "$($M.Id)"; Name = $M.Name; Upn = $M.Upn }) }
    }
    foreach ($A in @($Server.Assigned | Where-Object { $_.Type -eq 'User' })) {
        if (-not ($People | Where-Object { $_.Id -eq "$($A.PrincipalId)" })) { $People.Add([pscustomobject]@{ Id = "$($A.PrincipalId)"; Name = $A.Name; Upn = $null }) }
    }
    $Rows = @($People | Sort-Object Name | ForEach-Object {
            $P = $_
            $L = if ($Own.ContainsKey($P.Id)) { & $LevelOf $Own[$P.Id].Level } else { $Everyone }
            $Upn = if ($P.Upn) { $P.Upn } elseif ($Own.ContainsKey($P.Id)) { $Own[$P.Id].Upn } else { $null }
            @{
                person = if ($Upn) { "$($P.Name) ($Upn)" } else { "$($P.Name)" }
                level  = (& $LevelName $L)
                can    = if ($L) { $L.summary } else { 'A custom set of permissions; ask us for the detail.' }
                tone   = if (-not $L) { 'warn' } elseif ($L.number -ge 3) { 'warn' } else { 'pass' }
            }
        })
    $Higher = @($Rows | Where-Object { $_.level -ne (& $LevelName $Everyone) }).Count

    $AsOf = if ($GeneratedOn) { " as of $GeneratedOn" } else { '' }
    $blocks.Add((New-CippReportPage -Title "What we've set up" -Subtitle "Claude for Microsoft 365 at $TenantName$AsOf"))
    if ($ContactName) { $blocks.Add((New-CippReportParagraph -Html "<p>Dear $(& $enc $ContactName),</p>")) }
    $blocks.Add((New-CippReportParagraph -Html "<p>Claude, Anthropic's AI assistant, is now connected to Microsoft 365 at <b>$(& $enc $TenantName)</b>. This is a summary of what we set up: who can use it, what it can read and change for each of them, and the safeguards in place.</p>"))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = "$($Rows.Count)"; label = 'People who can use Claude' }
                @{ value = $(if ($Everyone) { "Level $($Everyone.number)" } else { 'Custom' }); label = $(if ($Everyone) { "Everyone: $($Everyone.name)" } else { 'Level for everyone' }) }
                @{ value = "$Higher"; label = 'People with a higher level' }
            )))

    # Anything not finished goes first, so it isn't missed.
    $Unfinished = [System.Collections.Generic.List[string]]::new()
    if (-not $S.Consented) { $Unfinished.Add("Microsoft's admin consent for Claude hasn't been given yet, so Claude can't connect.") }
    if ($S.Consented -and -not $S.Restricted) { $Unfinished.Add('Claude is not yet limited to named people: anyone in the business could connect it.') }
    if ($Access.Level -eq 'full' -and -not $Higher) { $Unfinished.Add('Everyone currently has full access, which Microsoft''s consent page gives by default. We will set the level you asked for.') }
    if ($Unfinished.Count -gt 0) {
        $blocks.Add((New-CippReportAlertBox -Title 'Still to finish' -Lines -Content (@($Unfinished | ForEach-Object { "$([char]0x2022) $_" }) -join "`n")))
    }

    $blocks.Add((New-CippReportTable -Title 'Who can use Claude' -Columns @(
                @{ header = 'Person'; key = 'person'; width = 2.4; bold = $true }
                @{ header = 'Level'; key = 'level'; width = 1.8; toneField = 'tone' }
                @{ header = 'Claude can'; key = 'can'; width = 3.2 }
            ) -Rows $Rows -Limit 100 -EmptyText 'Nobody can use Claude yet.'))
    $blocks.Add((New-CippReportNote -Text 'Claude only ever sees and does what the person using it could see and do themselves. Everyone else in the business is blocked from connecting it.'))

    # ------------------------------------------------------------------ what Claude can read
    $On = @($Config.readAreas | Where-Object { @($Access.ReadAreas) -contains $_.id })
    $Off = @($Config.readAreas | Where-Object { @($Access.ReadAreas) -notcontains $_.id })
    $ReadItems = [System.Collections.Generic.List[object]]::new()
    foreach ($A in $On) { $ReadItems.Add(@{ label = 'On'; text = "$($A.label): $($A.description)" }) }
    foreach ($A in $Off) { $ReadItems.Add(@{ label = 'Off'; text = "$($A.label): switched off for everyone." }) }
    if ($ReadItems.Count -gt 0) { $blocks.Add((New-CippReportBullets -Title 'What Claude can read' -Items @($ReadItems))) }

    # ------------------------------------------------------------------ safeguards
    $blocks.Add((New-CippReportPage -Title 'Keeping it safe' -Subtitle 'Safeguards in place, and what happens next'))
    $Yes = { param($V) if ($V -eq $true) { 'In place' } elseif ($V -eq $false) { 'Not in place' } else { 'To confirm' } }
    $Tone = { param($V) if ($V -eq $true) { 'pass' } elseif ($V -eq $false) { 'fail' } else { 'warn' } }
    $R = $S.Readiness
    $Guards = @(
        @{ what = 'Named people only'; detail = 'Only the people listed can connect Claude to Microsoft 365.'; V = [bool]$S.Restricted }
        @{ what = 'No unapproved apps'; detail = 'Staff can''t give apps access to company data themselves; they ask, and an administrator approves.'; V = $(if ($null -eq $S.UserConsent.Allowed) { $null } else { -not $S.UserConsent.Allowed }) }
        @{ what = 'App requests reviewed'; detail = 'Requests for new apps go to administrators to review.'; V = $S.AdminConsentRequests.Enabled }
        @{ what = 'Third-party backup'; detail = $(if ($R.Backup.Found) { "$(@($R.Backup.Products) -join ', ') protects your Microsoft 365 data." } else { 'A separate backup means anything changed or deleted can be put back.' }); V = $(if ($null -eq $R.Backup) { $null } else { [bool]$R.Backup.Found }) }
        @{ what = 'Microsoft Defender'; detail = $(if ($R.Defender.Found) { "$(@($R.Defender.Products) -join ' and ')." } else { 'Protects computers and email against malware and phishing.' }); V = $(if ($null -eq $R.Defender) { $null } else { [bool]$R.Defender.Found }) }
    )
    $blocks.Add((New-CippReportTable -Title 'Safeguards' -Columns @(
                @{ header = 'Safeguard'; key = 'what'; width = 1.8; bold = $true }
                @{ header = 'What it does'; key = 'detail'; width = 4.2 }
                @{ header = 'Status'; key = 'status'; width = 1.2; toneField = 'tone' }
            ) -Rows @($Guards | ForEach-Object { @{ what = $_.what; detail = $_.detail; status = (& $Yes $_.V); tone = (& $Tone $_.V) } })))
    $Missing = @($Guards | Where-Object { $_.V -eq $false -and $_.what -in @('Third-party backup', 'Microsoft Defender') } | ForEach-Object { $_.what.ToLower() -replace '^microsoft defender$', 'Microsoft Defender' })
    if ($Missing.Count -gt 0) {
        $AboveOne = ($Everyone -and $Everyone.number -gt 1) -or $Higher -gt 0 -or -not $Everyone
        $When = if ($AboveOne) { 'now that Claude can change things for some people' } else { 'before anyone has a level above Level 1' }
        $blocks.Add((New-CippReportInfoBox -Title 'Our recommendation' -Tone warn -Content "We recommend adding $($Missing -join ' and ') $When, and we can quote for it. Microsoft 365 Business Premium includes Microsoft Defender."))
    }

    $blocks.Add((New-CippReportBullets -Title 'What happens next' -Items @(
                @{ label = 'Connect'; text = 'Each person opens the connector settings in Claude (Settings > Connectors, or Customize > Connectors in the desktop app), connects Microsoft 365 and signs in with their work account.' }
                @{ label = 'Check before it acts'; text = 'In the Claude desktop app, Claude asks before it sends an email, invite or Teams message. Read what it is about to do before approving.' }
                @{ label = 'Changes'; text = 'To add or remove people, or change what Claude can do, email us. Changes take effect straight away; people may need to reconnect Microsoft 365 in Claude.' }
                @{ label = 'Something odd?'; text = 'If Claude does something unexpected, or an email seems to be trying to instruct it, tell us straight away.' }
            )))
    if ($PreparedBy) { $blocks.Add((New-CippReportParagraph -Html "<p>Kind regards,<br/>$(& $enc $PreparedBy)</p>")) }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Claude for Microsoft 365'
            covertitle         = 'Claude setup'
            coveraccent        = 'Summary'
            covertenant        = $TenantName
            coversubtitle      = "What we set up for Claude, Anthropic's AI assistant, at ${TenantName}: who can use it, what it can do, and the safeguards in place."
            covermeta          = "$(@($Rows).Count) $(if (@($Rows).Count -eq 1) { 'person' } else { 'people' }) $([char]0x00B7) $(if ($Everyone) { "Level $($Everyone.number) for everyone" } else { 'custom permissions' })"
            covermetanote      = 'Setup summary'
            coverfooternote    = "Prepared for $TenantName"
            coverfallbackimage = '/reportImages/city.jpg'
            coverpanel         = 'true'
            footerlabel        = "$TenantName $([char]0x2014) Claude setup summary"
        }
    }
}
