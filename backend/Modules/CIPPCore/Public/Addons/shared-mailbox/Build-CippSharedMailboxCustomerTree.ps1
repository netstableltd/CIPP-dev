function Build-CippSharedMailboxCustomerTree {
    <#
    .SYNOPSIS
        Composes the customer PDF for a new shared mailbox: the choices to make, what each option means,
        what we recommend, and what to reply with. A component tree for ConvertTo-CippReportPdf.

    .PARAMETER MailboxName
        Optional: the mailbox asked for (for example "info@contoso.co.uk"), named in the letter.

    .OUTPUTS
        @{ Blocks; Variables }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantName,
        [string]$MailboxName,
        [string]$ContactName,
        [string]$PreparedBy
    )

    $Options = Get-CIPPSharedMailboxOptions
    $enc = { param($t) [System.Net.WebUtility]::HtmlEncode([string]$t) }
    $Bullet = [char]0x2022
    $blocks = [System.Collections.Generic.List[object]]::new()
    $Questions = @($Options.questions)

    # ------------------------------------------------------------------ Your request
    $blocks.Add((New-CippReportPage -Title 'Your request' -Subtitle 'A shared mailbox for your team'))
    if ($ContactName) { $blocks.Add((New-CippReportParagraph -Html "<p>Dear $(& $enc $ContactName),</p>")) }
    $What = if ($MailboxName) { "a shared mailbox, <b>$(& $enc $MailboxName)</b>," } else { 'a shared mailbox' }
    $blocks.Add((New-CippReportParagraph -Html "<p>You have asked for $What at <b>$(& $enc $TenantName)</b>. A shared mailbox lets several people read and send email from one address, such as info@ or accounts@, each signing in as themselves.</p>"))
    $blocks.Add((New-CippReportParagraph -Text "There are $($Questions.Count) choices to make about how it works day to day. Each one is explained on the next pages, with what it means for your team and the option we recommend. If you are happy with all our recommendations, just tell us so with the mailbox name and who needs access."))
    $blocks.Add((New-CippReportBullets -Title 'What we always do' -Items @($Options.alwaysDone | ForEach-Object { @{ label = $_.label; text = $_.text } })))
    $blocks.Add((New-CippReportInfoBox -Title 'Is a shared mailbox the right fit?' -Content ("A shared mailbox suits a team answering email from one address. Other options can suit better:`n" + (@($Options.alternatives | ForEach-Object { "$Bullet $($_.label): $($_.text)" }) -join "`n"))))

    # ------------------------------------------------------------------ The choices
    $Number = 0
    $PerPage = 3
    for ($i = 0; $i -lt $Questions.Count; $i += $PerPage) {
        $Last = [math]::Min($i + $PerPage, $Questions.Count)
        $blocks.Add((New-CippReportPage -Title 'The choices' -Subtitle "Questions $($i + 1) to $Last of $($Questions.Count)"))
        foreach ($Q in $Questions[$i..($Last - 1)]) {
            $Number++
            $blocks.Add((New-CippReportHeading -Title "$Number. $($Q.title)"))
            $blocks.Add((New-CippReportParagraph -Html "<p><b>$(& $enc $Q.question)</b></p>"))
            $blocks.Add((New-CippReportTable -Columns @(
                        @{ header = 'Option'; key = 'option'; width = 1.6; bold = $true; toneField = 'tone' }
                        @{ header = 'What it means'; key = 'means'; width = 2.4 }
                        @{ header = 'Good'; key = 'pros'; width = 2.1 }
                        @{ header = 'Watch out'; key = 'cons'; width = 2.1 }
                    ) -Rows @($Q.options | ForEach-Object {
                            @{
                                option = if ($_.recommended) { "$($_.label) (recommended)" } else { $_.label }
                                tone   = if ($_.recommended) { 'pass' } else { '' }
                                means  = "$($_.summary) Suits: $($_.suits.Substring(0,1).ToLower())$($_.suits.Substring(1))"
                                pros   = (@($_.pros) -join ' ')
                                cons   = if (@($_.cons).Count) { @($_.cons) -join ' ' } else { 'Nothing to note.' }
                            }
                        })))
        }
    }

    # ------------------------------------------------------------------ What we need from you
    $blocks.Add((New-CippReportPage -Title 'What we need from you' -Subtitle 'Reply by email with your choices'))
    $blocks.Add((New-CippReportParagraph -Text 'Please reply to us by email with the options you would like. You can copy the list below into your reply; where you leave a choice blank we will use our recommendation.'))
    $Reply = [System.Collections.Generic.List[string]]::new()
    $Reply.Add("A. Mailbox name and address$(if ($MailboxName) { " (you asked for $MailboxName)" }):")
    $Reply.Add('B. Any other addresses it should receive email for:')
    $Reply.Add('C. Who needs access (names):')
    $Number = 0
    foreach ($Q in $Questions) {
        $Number++
        $Rec = @($Q.options | Where-Object { $_.recommended } | Select-Object -First 1)
        $Reply.Add("$Number. $($Q.title) ($(@($Q.options.label) -join ' / '); we suggest $($Rec.label.ToLower())):")
    }
    $blocks.Add((New-CippReportInfoBox -Title 'Your reply' -Lines -Content ($Reply -join "`n")))
    $blocks.Add((New-CippReportNote -Text 'Once it is set up, we will send you a short guide for your team on adding the mailbox to Outlook and sending from it.'))
    if ($PreparedBy) { $blocks.Add((New-CippReportParagraph -Html "<p>Kind regards,<br/>$(& $enc $PreparedBy)</p>")) }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Shared mailbox'
            covertenant        = $TenantName
            coversubtitle      = "Your choices for a new shared mailbox$(if ($MailboxName) { " ($MailboxName)" }) at $TenantName."
            covermeta          = "$($Questions.Count) choices $([char]0x00B7) what each means $([char]0x00B7) what we recommend"
            covermetanote      = 'Information for you'
            coverfooternote    = "Prepared for $TenantName"
            coverfallbackimage = '/reportImages/city.jpg'
            coverpanel         = 'true'
            footerlabel        = "$TenantName $([char]0x2014) Shared mailbox"
        }
    }
}
