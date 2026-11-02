function Build-CippSharedMailboxSummaryTree {
    <#
    .SYNOPSIS
        Composes the "your shared mailbox is ready" PDF for the customer: how the mailbox is set up (read
        from the tenant), anything not finished, and a guide for the team on adding it to Outlook, sending
        from it and working together in it, matched to the choices made. A component tree for
        ConvertTo-CippReportPdf.

    .PARAMETER Status
        Output of Get-CIPPSharedMailboxStatus.

    .PARAMETER Answers
        The customer's choices (Resolve-CIPPSharedMailboxAnswers). Needed because some (how it appears in
        Outlook, the signature) can't be read from the tenant.

    .PARAMETER Guide
        Optional output of ConvertFrom-CIPPDocxGuide: the MSP's own step-by-step guide, added at the end.

    .OUTPUTS
        @{ Blocks; Variables }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantName,
        [Parameter(Mandatory)]$Status,
        $Answers,
        [string]$ContactName,
        [string]$PreparedBy,
        $Guide
    )

    $Options = Get-CIPPSharedMailboxOptions
    $A = Resolve-CIPPSharedMailboxAnswers -Answers $Answers
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $Label = { param($Q, $Id) (@($Options.questions | Where-Object id -eq $Q)[0].options | Where-Object id -eq $Id | Select-Object -First 1).label }
    $S = $Status
    $Address = $S.Address
    $HasGuide = $Guide -and @($Guide.Blocks).Count -gt 0
    $blocks = [System.Collections.Generic.List[object]]::new()
    $Open = [System.Collections.Generic.List[string]]::new()

    # ------------------------------------------------------------------ Ready
    $blocks.Add((New-CippReportPage -Title 'Your shared mailbox' -Subtitle "$($S.DisplayName) ($Address)"))
    if ($ContactName) { $blocks.Add((New-CippReportParagraph -Html "<p>Dear $(& $enc $ContactName),</p>")) }
    $blocks.Add((New-CippReportParagraph -Html "<p>Your shared mailbox <b>$(& $enc $S.DisplayName)</b> (<b>$(& $enc $Address)</b>) is set up at <b>$(& $enc $TenantName)</b>. This is how it works, and a guide for your team is on the following pages.</p>"))

    $Holders = if ($S.Group) { @($S.Group.Members) } else { @($S.FullAccess | Where-Object { -not $_.IsGroup }) }
    $Who = if ($S.Group) { "Members of the group $($S.Group.Name): $(@($Holders.Name) -join ', ')" } elseif ($Holders.Count) { @($Holders.Name) -join ', ' } else { 'Nobody yet' }
    if (-not $Holders.Count) { $Open.Add('Nobody has access yet: tell us who should have it.') }
    $Sending = switch ($A.send) {
        'sendAs' { "As $Address (recipients see only the shared address)" }
        'sendOnBehalf' { "On behalf of $Address (recipients see ""name on behalf of $($S.DisplayName)"")" }
        default { 'Not allowed: people can read and file email only' }
    }
    $SizeText = if ($S.SizeBytes) { "$([math]::Round($S.SizeBytes / 1GB, 2)) GB used" } else { 'Empty' }
    $Rows = @(
        @{ what = 'Address'; how = (@($Address) + @($S.Aliases | Where-Object { $_ -ne $Address }) -join ', ') }
        @{ what = 'Who has access'; how = $Who }
        @{ what = 'Sending'; how = $Sending }
        @{ what = 'Sent emails'; how = $(if ($S.MessageCopySentAs) { 'Copied to the shared mailbox''s Sent Items (and kept in the sender''s own)' } else { 'Kept only in the sender''s own Sent Items' }) }
        @{ what = 'In Outlook'; how = (& $Label 'outlook' $A.outlook) }
        @{ what = 'Signature'; how = (& $Label 'signature' $A.signature) }
        @{ what = 'Address book'; how = $(if ($S.Hidden) { 'Hidden' } else { 'Shown' }) }
        @{ what = 'Who can email it'; how = $(if ($S.InternalOnly) { 'Only people in the business' } else { 'Anyone' }) }
        @{ what = 'Size'; how = "$SizeText of $(if ($S.Licensed) { '100 GB (licensed)' } else { '50 GB' })$(if ($S.ArchiveActive) { ', with an archive' })" }
        @{ what = 'Sign-in'; how = $(if ($S.SignInBlocked) { 'Blocked: people reach it through their own accounts' } elseif ($null -eq $S.SignInBlocked) { 'Not checked' } else { 'Allowed' }) }
    )
    $blocks.Add((New-CippReportTable -Columns @(
                @{ header = 'Setting'; key = 'what'; width = 1.6; bold = $true }
                @{ header = 'How it is set up'; key = 'how'; width = 5 }
            ) -Rows $Rows))
    if ($A.size -eq 'licensed' -and -not $S.Licensed) { $Open.Add('It needs an Exchange Online licence for the larger size, archive or legal hold you asked for; we will arrange this.') }
    if ($A.signature -eq 'rule' -and -not $S.SignatureRule) { $Open.Add('The automatic signature isn''t set up yet.') }
    if ($S.SignInBlocked -eq $false) { $Open.Add('Sign-in to the mailbox itself is still allowed.') }
    if ($Open.Count) { $blocks.Add((New-CippReportAlertBox -Title 'Still to do' -Lines -Content ($Open -join "`n"))) }

    # ------------------------------------------------------------------ Adding it to Outlook
    $blocks.Add((New-CippReportPage -Title 'For your team' -Subtitle 'Adding the shared mailbox'))
    $blocks.Add((New-CippReportParagraph -Text 'Everyone uses their own sign-in; nobody needs a password for the shared mailbox. New access can take up to an hour to appear.'))
    $AutoAppears = $A.outlook -eq 'automap' -and $A.grantVia -eq 'people'
    $Steps = [System.Collections.Generic.List[object]]::new()
    if ($AutoAppears) {
        $Steps.Add(@{ label = 'Classic Outlook (Windows)'; text = "Nothing to do: $($S.DisplayName) appears in the folder list below your own mailbox. If it isn't there after an hour, close Outlook and open it again." })
    } elseif ($A.outlook -eq 'account') {
        $Steps.Add(@{ label = 'Classic Outlook (Windows)'; text = "Add it as a second account: File > Add Account, type $Address, and if asked to sign in use your own work email and password. Close and reopen Outlook. It then shows as its own mailbox, with its own Inbox and Sent Items." })
    } else {
        $Steps.Add(@{ label = 'Classic Outlook (Windows)'; text = "File > Account Settings > Account Settings, double-click your own account, then More Settings > Advanced > Add, type $Address and press OK on each window. Or add it as a second account: File > Add Account, type $Address, and sign in with your own work account." })
    }
    $Steps.Add(@{ label = 'New Outlook and Outlook on the web'; text = "Look under Shared with me in the folder list. If it isn't there, right-click Shared with me, choose Add shared folder or mailbox and type $Address. To open it on its own in a browser: your profile picture > Open another mailbox." })
    $Steps.Add(@{ label = 'Outlook on a phone'; text = "Open the Outlook app, tap your profile picture > Add account > Add shared mailbox, and choose $Address." })
    $blocks.Add((New-CippReportBullets -Title 'Adding it' -Items @($Steps)))

    # ------------------------------------------------------------------ Sending
    if ($A.send -ne 'none') {
        $SendItems = [System.Collections.Generic.List[object]]::new()
        $SendItems.Add(@{ label = 'Replying'; text = 'Replies to emails in the shared mailbox usually go from the shared address automatically. Check the From line before sending.' })
        if ($A.outlook -eq 'account') {
            $SendItems.Add(@{ label = 'New emails'; text = 'Start the email from inside the shared mailbox''s account and it goes from the shared address.' })
        } else {
            $SendItems.Add(@{ label = 'New emails in classic Outlook'; text = "A new email starts from your own address. Show the From button once (Options > From), then click From and choose $Address; the first time choose Other email address and type it. Outlook remembers it after that." })
            $SendItems.Add(@{ label = 'New Outlook and the web'; text = "Click From at the top of the email and choose $Address." })
        }
        $SendItems.Add(@{ label = 'On a phone'; text = 'Write the email from the shared mailbox''s account in the Outlook app.' })
        if ($A.send -eq 'sendOnBehalf') { $SendItems.Add(@{ label = 'What people see'; text = "Emails show as ""Your name on behalf of $($S.DisplayName)""." }) }
        $SendItems.Add(@{ label = 'Sent emails'; text = $(if ($S.MessageCopySentAs) { 'A copy goes in the shared mailbox''s Sent Items, so everyone can see what has been sent. You keep a copy in your own Sent Items too.' } else { 'Sent emails stay in your own Sent Items only.' }) })
        $blocks.Add((New-CippReportBullets -Title 'Sending from it' -Items @($SendItems)))
        if ($HasGuide) { $blocks.Add((New-CippReportNote -Text 'The step-by-step guide at the end of this document shows sending from the shared address, with pictures.')) }

        $Sig = switch ($A.signature) {
            'rule' { 'The signature is added automatically to every email sent from the shared address after you press Send. You won''t see it while writing, so don''t add it yourself.' }
            'tool' { 'Your signature service adds the shared mailbox''s signature when you send from the shared address.' }
            default {
                if ($A.outlook -eq 'account') { 'In classic Outlook, set the shared signature for the shared mailbox''s account: File > Options > Mail > Signatures, choose the shared mailbox under E-mail account, and pick the signature for new messages and replies.' }
                else { 'Save the shared signature as a second signature (File > Options > Mail > Signatures > New in classic Outlook; Settings > Account > Signatures in new Outlook), and pick it from Signature when sending from the shared address.' }
            }
        }
        $blocks.Add((New-CippReportInfoBox -Title 'Signature' -Content $Sig))
    }

    # ------------------------------------------------------------------ Working together
    $blocks.Add((New-CippReportBullets -Title 'Working together' -Items @($Options.teamTips | ForEach-Object { @{ label = $_.label; text = $_.text } })))
    $blocks.Add((New-CippReportNote -Text 'To give someone access, take it away, or change any of these settings, just ask us.'))
    if ($PreparedBy) { $blocks.Add((New-CippReportParagraph -Html "<p>Kind regards,<br/>$(& $enc $PreparedBy)</p>")) }

    if ($HasGuide) {
        $blocks.Add((New-CippReportPage -Title $(if ($Guide.Title) { $Guide.Title } else { 'Sending from a shared mailbox' }) -Subtitle $Guide.Subtitle))
        foreach ($B in @($Guide.Blocks)) { $blocks.Add($B) }
    }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Shared mailbox'
            covertenant        = $TenantName
            coversubtitle      = "$($S.DisplayName) ($Address) is ready."
            covermeta          = "How it is set up $([char]0x00B7) adding it to Outlook $([char]0x00B7) sending from it"
            covermetanote      = 'For you and your team'
            coverfooternote    = "Prepared for $TenantName"
            coverfallbackimage = '/reportImages/city.jpg'
            coverpanel         = 'true'
            footerlabel        = "$TenantName $([char]0x2014) $Address"
        }
    }
}
