function Build-CippClaudeConnectorCustomerTree {
    <#
    .SYNOPSIS
        Composes the customer information PDF for Claude for Microsoft 365 as a component tree for
        ConvertTo-CippReportPdf.

    .DESCRIPTION
        For a customer who has asked for Claude to have access to Microsoft 365: what we recommend having
        first (third-party backup, Entra ID P1, Microsoft Defender, with Business Premium as our default),
        filled in from the tenant (Get-CIPPClaudeConnectorReadiness); the four access levels with what each
        lets Claude do and its pros and cons (Config/Addons/claude-m365/ClaudeConnectorAccess.json); the other choices; and
        what to reply with.

    .PARAMETER TenantName
        Customer name.

    .PARAMETER Readiness
        Output of Get-CIPPClaudeConnectorReadiness.

    .PARAMETER ContactName
        Optional: who the letter is addressed to.

    .PARAMETER PreparedBy
        Optional: who it is from, shown at the end.

    .OUTPUTS
        @{ Blocks; Variables }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantName,
        $Readiness,
        [string]$ContactName,
        [string]$PreparedBy
    )

    $Config = Get-CIPPClaudeConnectorAccessConfig
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $Name = & $enc $TenantName
    $R = $Readiness
    $blocks = [System.Collections.Generic.List[object]]::new()
    $Missing = [System.Collections.Generic.List[string]]::new()

    # ------------------------------------------------------------------ Your request
    $blocks.Add((New-CippReportPage -Title 'Your request' -Subtitle 'Giving Claude access to Microsoft 365'))
    if ($ContactName) { $blocks.Add((New-CippReportParagraph -Html "<p>Dear $(& $enc $ContactName),</p>")) }
    $blocks.Add((New-CippReportParagraph -Html "<p>You have asked for <b>Claude</b>, Anthropic's AI assistant, to have access to Microsoft 365 at <b>$Name</b>. There are various ways to do that, from letting Claude search and read, through to letting it send email and change files on someone's behalf. <b>We recommend you start with limited access and add to it from there.</b></p>"))
    $blocks.Add((New-CippReportParagraph -Text 'Claude only ever sees what the person using it can already see. The choices are about which of those things it can read, and whether it can change or send anything.'))

    # ------------------------------------------------------------------ Before you start
    $blocks.Add((New-CippReportHeading -Title 'Before you start'))
    $blocks.Add((New-CippReportParagraph -Text 'We checked your Microsoft 365 for the things we recommend having in place before giving an AI assistant access.'))

    $BackupHave = $null; $BackupText = ''
    if ($null -eq $R.Backup) {
        $BackupText = "We couldn't check this automatically; we will confirm it with you."
    } elseif ($R.Backup.Barracuda) {
        $BackupHave = $true; $BackupText = "You have $((@($R.Backup.Products | Where-Object { $_ -match '(?i)barracuda' }) | Select-Object -First 1))."
    } elseif ($R.Backup.Found) {
        $BackupHave = $true; $BackupText = "You have $(@($R.Backup.Products) -join ', '). We use Barracuda Cloud-to-Cloud Backup, but any good third-party backup will do."
    } else {
        $BackupHave = $false; $BackupText = "We couldn't find a third-party backup of your Microsoft 365. We recommend Barracuda Cloud-to-Cloud Backup, which we can set up for you."
        $Missing.Add('a third-party backup (Barracuda Cloud-to-Cloud Backup)')
    }
    $P1Text = if ($R.EntraP1 -eq $true) { 'You have Entra ID P1, so we can control access with a security group.' }
    elseif ($R.EntraP1 -eq $false) { $Missing.Add('Entra ID P1 licences'); "You don't currently have Entra ID P1. We can still limit access by adding each person one at a time, but it is harder to manage." }
    else { "We couldn't check your licences; we will confirm this with you." }
    $DefText = if ($R.Defender.Found) { "You already have $(@($R.Defender.Products) -join ' and ') as part of your licences." }
    elseif ($null -ne $R.Defender) { $Missing.Add('Microsoft Defender'); "You don't currently have Microsoft Defender in your licences." }
    else { "We couldn't check your licences; we will confirm this with you." }
    $Tone = { param($Have) if ($Have -eq $true) { 'pass' } elseif ($Have -eq $false) { 'fail' } else { 'warn' } }
    $HaveText = { param($Have) if ($Have -eq $true) { 'Yes' } elseif ($Have -eq $false) { 'Not yet' } else { 'To confirm' } }
    $DefHave = if ($null -eq $R.Defender) { $null } else { [bool]$R.Defender.Found }

    $Rows = @(
        @{ what = 'Third-party backup'; why = 'Microsoft keeps your data running, but recovering from mistakes is your responsibility. A separate backup means anything Claude (or anyone) changes or deletes can be put back.'; have = (& $HaveText $BackupHave); tone = (& $Tone $BackupHave) }
        @{ what = 'Microsoft Entra ID P1'; why = 'Lets us control who can use Claude with a security group, and add Conditional Access such as requiring MFA.'; have = (& $HaveText $R.EntraP1); tone = (& $Tone $R.EntraP1) }
        @{ what = 'Microsoft Defender'; why = 'Protects computers and email against malware, phishing and malicious links, which matter more once an assistant is reading and acting on email.'; have = (& $HaveText $DefHave); tone = (& $Tone $DefHave) }
    )
    $blocks.Add((New-CippReportTable -Columns @(
                @{ header = 'What'; key = 'what'; width = 1.5; bold = $true }
                @{ header = 'Why we recommend it'; key = 'why'; width = 4.2 }
                @{ header = 'You have it'; key = 'have'; width = 1.1; toneField = 'tone' }
            ) -Rows $Rows))
    $blocks.Add((New-CippReportBullets -Items @(
                @{ label = 'Backup'; text = $BackupText }
                @{ label = 'Entra ID P1'; text = $P1Text }
                @{ label = 'Defender'; text = $DefText }
            )))

    $BpIntro = 'Microsoft 365 Business Premium is our default recommendation for businesses. As well as the Office apps, email and Teams, it includes Entra ID P1 (security groups and Conditional Access), Microsoft Defender for Business for your computers, Defender for Office 365 for your email, and Intune to manage devices. That covers the licence items above in one subscription.'
    if ($R.BusinessPremium) {
        $blocks.Add((New-CippReportInfoBox -Title 'Microsoft 365 Business Premium' -Tone ok -Content "$BpIntro You already have Business Premium."))
    } elseif ($R.Suite) {
        $blocks.Add((New-CippReportInfoBox -Title 'Microsoft 365 Business Premium' -Content "$BpIntro You have $($R.Suite), which already includes what Business Premium would add."))
    } else {
        $blocks.Add((New-CippReportInfoBox -Title 'Microsoft 365 Business Premium' -Tone warn -Content "$BpIntro You don't currently have Business Premium; we can quote for moving to it."))
        if ($Missing -contains 'Entra ID P1 licences' -or $Missing -contains 'Microsoft Defender') { $Missing.Add('Microsoft 365 Business Premium') }
    }

    # ------------------------------------------------------------------ Access levels
    $blocks.Add((New-CippReportPage -Title 'Access levels' -Subtitle 'From read only to handing over the keys'))
    $blocks.Add((New-CippReportParagraph -Text 'A good way to use an AI assistant is for research in read-only mode: Claude can search and read, so it can find, summarise and draft answers, but it cannot change anything. That keeps the risks low. You can go all the way to handing Claude the keys, but you need to understand the risks that brings. These are the levels we suggest.'))
    $blocks.Add((New-CippReportTable -Columns @(
                @{ header = 'Level'; key = 'level'; width = 1.9; bold = $true }
                @{ header = 'Claude can'; key = 'can'; width = 3.8 }
                @{ header = 'Risk'; key = 'risk'; width = 1.1; toneField = 'tone' }
            ) -Rows @($Config.levels | ForEach-Object {
                    @{
                        level = "$($_.number). $($_.name)"
                        can   = (@($_.canDo | Where-Object { $_ -notmatch '^Everything in Level' }) -join '. ')
                        risk  = $_.risk
                        tone  = $(switch ($_.number) { 1 { 'pass' } 2 { 'pass' } 3 { 'warn' } default { 'fail' } })
                    }
                })))
    $blocks.Add((New-CippReportNote -Text 'Each level includes everything in the levels before it. Different people can have different levels.'))
    $blocks.Add((New-CippReportBullets -Title 'You also choose' -Items @(
                @{ label = 'Who'; text = 'Only the people you name can use Claude with Microsoft 365. Everyone else is blocked.' }
                @{ label = 'Different levels for different people'; text = 'For example Level 1 for everyone and Level 2 for two people who want help with email.' }
                @{ label = 'What Claude can read'; text = "Any of these can be switched off for everyone: $((@($Config.readAreas | ForEach-Object { $_.noun }) -join ', '))." }
            )))

    # Two levels to a page: the lower-risk pair, then the higher-risk pair.
    $Pages = @(
        @{ Title = 'Levels 1 and 2'; Subtitle = 'Lower risk: Claude reads, and at most prepares'; Levels = @($Config.levels | Where-Object { $_.number -le 2 }) }
        @{ Title = 'Levels 3 and 4'; Subtitle = 'Higher risk: Claude acts on the person''s behalf'; Levels = @($Config.levels | Where-Object { $_.number -ge 3 }) }
    )
    foreach ($Pg in $Pages) {
        $blocks.Add((New-CippReportPage -Title $Pg.Title -Subtitle $Pg.Subtitle))
        foreach ($L in $Pg.Levels) {
            $blocks.Add((New-CippReportHeading -Title "Level $($L.number): $($L.name)"))
            $Suits = $L.suits.Substring(0, 1).ToLower() + $L.suits.Substring(1)
            $blocks.Add((New-CippReportParagraph -Html "<p><i>$(& $enc $L.tagline).</i> Risk: <b>$(& $enc $L.risk.ToLower())</b>. Suits: $(& $enc $Suits).</p>"))
            $Items = [System.Collections.Generic.List[object]]::new()
            foreach ($C in $L.canDo) { $Items.Add(@{ label = 'Can'; text = $C }) }
            foreach ($C in @($L.cannotDo)) { $Items.Add(@{ label = 'Cannot'; text = $C }) }
            $blocks.Add((New-CippReportBullets -Items @($Items)))
            $blocks.Add((New-CippReportInfoBoxColumns -Columns 2 -Items @(
                        @{ title = 'Pros'; tone = 'ok'; content = (@($L.pros | ForEach-Object { "$([char]0x2022) $_" }) -join "`n") }
                        @{ title = 'Cons'; tone = 'warn'; content = (@($L.cons | ForEach-Object { "$([char]0x2022) $_" }) -join "`n") }
                    )))
        }
    }

    # ------------------------------------------------------------------ Other choices and safeguards
    $blocks.Add((New-CippReportPage -Title 'Next steps' -Subtitle 'How we keep it safe, and what we need from you'))
    $blocks.Add((New-CippReportBullets -Title 'How we keep it safe' -Items @(
                @{ label = 'Named people only'; text = 'Claude is blocked for anyone not on your list.' }
                @{ label = 'No surprise apps'; text = 'Staff can no longer approve apps that want access to company data themselves; they send a request, and an administrator approves it.' }
                @{ label = 'Approval before sending'; text = 'In the Claude desktop app, Claude asks the person to approve every email, invite or Teams message before it is sent.' }
                @{ label = 'Easy to change'; text = 'Levels can be raised, lowered or switched off at any time, straight away.' }
            )))

    # ------------------------------------------------------------------ What we need from you
    $blocks.Add((New-CippReportHeading -Title 'What we need from you'))
    $blocks.Add((New-CippReportParagraph -Text 'Please reply to us by email with the options you would like. You can copy the list below into your reply.'))
    $Reply = [System.Collections.Generic.List[string]]::new()
    $Reply.Add('1. Who should be able to use Claude:')
    $Reply.Add('2. Level for everyone (we suggest Level 1, Read only):')
    $Reply.Add('3. Anyone who needs a higher level, and which level:')
    $Reply.Add('4. Anything Claude should NOT read (email, calendar, files, Teams chats, Teams meetings):')
    if ($Missing.Count -gt 0) { $Reply.Add("5. Would you like a quote for: $($Missing -join '; ')?") }
    $blocks.Add((New-CippReportInfoBox -Title 'Your reply' -Lines -Content ($Reply -join "`n")))
    if ($PreparedBy) { $blocks.Add((New-CippReportParagraph -Html "<p>Kind regards,<br/>$(& $enc $PreparedBy)</p>")) }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Claude for Microsoft 365'
            covertenant        = $TenantName
            coversubtitle      = "Your options for giving Claude, Anthropic's AI assistant, access to Microsoft 365 at $TenantName."
            covermeta          = "4 access levels $([char]0x00B7) what we recommend first $([char]0x00B7) what we need from you"
            covermetanote      = 'Information for you'
            coverfooternote    = "Prepared for $TenantName"
            coverfallbackimage = '/reportImages/city.jpg'
            # A white panel behind the cover text, so it reads over the branding's cover photo.
            coverpanel         = 'true'
            footerlabel        = "$TenantName $([char]0x2014) Claude for Microsoft 365"
        }
    }
}
