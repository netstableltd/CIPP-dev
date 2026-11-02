function Set-CIPPSharedMailbox {
    <#
    .SYNOPSIS
        Creates a shared mailbox, or brings an existing one in line with the customer's answers: who has
        access and how, sending, sent copies, address book, who can email it, signature rule, archive,
        regional settings and blocked sign-in.

    .DESCRIPTION
        Safe to run again: each step checks what is already in place and only changes what differs. Every
        step is reported (Step, Status: Success, Info, Warning or Error, Message); a failed step doesn't
        stop the others, except that nothing runs if the mailbox can't be found or created.

        Access (answers from Resolve-CIPPSharedMailboxAnswers):
          grantVia people  Full Access to each person, with automapping when outlook is automap.
          grantVia group   a mail-enabled security group (GroupName, made if missing, hidden from the
                           address book) gets Full Access; the people are made its members. Automapping
                           doesn't work through groups, so each person adds the mailbox themselves.
          send             sendAs, sendOnBehalf or none, for the same people (or the group). The other way
                           of sending is removed from them, since granting both confuses Outlook.
        People already holding access who aren't on the list are left alone unless RemoveOthers.
        Automapping can't be read or changed on an existing grant; ReapplyAccess removes and re-adds the
        listed people's Full Access so it matches the outlook answer.

    .PARAMETER Identity
        An existing mailbox (address). Omit with New.

    .PARAMETER New
        Create the mailbox: @{ DisplayName; Address; Aliases = @() }. If the address is already a shared
        mailbox it is used as it is.

    .PARAMETER People
        Sign-in names (UPNs) of the people who need access.

    .PARAMETER SignatureHtml
        The signature the rule adds, for signature = rule. Needed when the rule doesn't exist yet.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [string]$Identity,
        $New,
        [string[]]$People = @(),
        $Answers,
        [string]$GroupName,
        [string]$SignatureHtml,
        [bool]$EnableArchive = $false,
        [bool]$BlockSignIn = $true,
        [bool]$RemoveOthers = $false,
        [bool]$ReapplyAccess = $false,
        [string]$Language,
        [string]$TimeZone,
        $Headers,
        [string]$APIName = 'Shared mailbox setup'
    )

    $A = Resolve-CIPPSharedMailboxAnswers -Answers $Answers
    $Defaults = (Get-CIPPSharedMailboxOptions).defaults
    if (-not $Language) { $Language = $Defaults.language }
    if (-not $TimeZone) { $TimeZone = $Defaults.timeZone }
    $Steps = [System.Collections.Generic.List[object]]::new()
    $Add = {
        param($Step, $Status, $Message)
        $Steps.Add([pscustomobject]@{ Step = $Step; Status = $Status; Message = $Message })
        $Sev = switch ($Status) { 'Error' { 'Error' } 'Warning' { 'Warning' } default { 'Info' } }
        if ($Status -ne 'Info') { Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "$($Step): $Message" -Sev $Sev }
    }
    $Err = { param($E) (Get-CippException -Exception $E).NormalizedError }
    $Exo = { param($Cmdlet, $Params, $Anchor) if ($Anchor) { New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams $Params -Anchor $Anchor } else { New-ExoRequest -tenantid $TenantFilter -cmdlet $Cmdlet -cmdParams $Params } }

    # ------------------------------------------------------------------ The mailbox
    $Mailbox = $null
    if ($New) {
        $Address = "$($New.Address)".Trim().ToLowerInvariant()
        $Existing = try { & $Exo 'Get-Recipient' @{ Identity = $Address } | Select-Object -First 1 } catch { $null }
        if ($Existing -and "$($Existing.RecipientTypeDetails)" -ne 'SharedMailbox') {
            & $Add 'Mailbox' 'Error' "$Address is already used by $($Existing.DisplayName) ($($Existing.RecipientTypeDetails)). Choose another address."
            return [pscustomobject]@{ Address = $Address; Steps = @($Steps) }
        }
        if ($Existing) {
            & $Add 'Mailbox' 'Info' "$Address is already a shared mailbox, so it was set up as it is."
            $Identity = $Address
        } else {
            try {
                $LocalPart = ($Address -split '@')[0]
                $Created = & $Exo 'New-Mailbox' @{ Shared = $true; Name = $LocalPart; Alias = ($LocalPart -replace '[^A-Za-z0-9._-]', ''); DisplayName = "$($New.DisplayName)".Trim(); PrimarySmtpAddress = $Address }
                & $Add 'Mailbox' 'Success' "Created the shared mailbox $($New.DisplayName) ($Address)."
                $Identity = $Address
                # A new mailbox takes a little while to be usable everywhere.
                for ($i = 0; $i -lt 8 -and -not $Mailbox; $i++) {
                    Start-Sleep -Seconds 5
                    $Mailbox = try { & $Exo 'Get-Mailbox' @{ Identity = $Address } | Select-Object -First 1 } catch { $null }
                }
                if (-not $Mailbox -and $Created) { $Mailbox = $Created }
            } catch {
                & $Add 'Mailbox' 'Error' "Couldn't create $($Address): $(& $Err $_)"
                return [pscustomobject]@{ Address = $Address; Steps = @($Steps) }
            }
        }
    }
    if (-not $Mailbox) {
        $Mailbox = try { & $Exo 'Get-Mailbox' @{ Identity = $Identity } | Select-Object -First 1 } catch { $null }
    }
    if (-not $Mailbox) {
        & $Add 'Mailbox' 'Error' "Couldn't find the mailbox $Identity."
        return [pscustomobject]@{ Address = $Identity; Steps = @($Steps) }
    }
    $Address = "$($Mailbox.PrimarySmtpAddress)"
    if ("$($Mailbox.RecipientTypeDetails)" -ne 'SharedMailbox') {
        & $Add 'Mailbox' 'Error' "$Address is a $($Mailbox.RecipientTypeDetails), not a shared mailbox. Convert it first if that is intended."
        return [pscustomobject]@{ Address = $Address; Steps = @($Steps) }
    }

    # Extra addresses
    $Wanted = @($New.Aliases | Where-Object { "$_".Trim() } | ForEach-Object { "$_".Trim().ToLowerInvariant() })
    $Have = @($Mailbox.EmailAddresses | ForEach-Object { ("$_" -replace '^smtp:', '').ToLowerInvariant() })
    $Missing = @($Wanted | Where-Object { $Have -notcontains $_ })
    if ($Missing.Count) {
        try {
            $null = & $Exo 'Set-Mailbox' @{ Identity = $Address; EmailAddresses = @{ '@odata.type' = '#Exchange.GenericHashTable'; Add = $Missing } } $Address
            & $Add 'Addresses' 'Success' "Added $($Missing -join ', ')."
        } catch { & $Add 'Addresses' 'Error' "Couldn't add $($Missing -join ', '): $(& $Err $_)" }
    }

    # ------------------------------------------------------------------ Sign-in
    $UserId = "$($Mailbox.ExternalDirectoryObjectId)"
    if ($BlockSignIn -and $UserId) {
        try {
            $User = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)?`$select=accountEnabled,onPremisesSyncEnabled" -tenantid $TenantFilter -noPagination $true
            if ($User.onPremisesSyncEnabled) { & $Add 'Sign-in' 'Warning' 'The mailbox account is synced from on-premises Active Directory: block its sign-in there.' }
            elseif ($User.accountEnabled) {
                $null = New-GraphPOSTRequest -uri "https://graph.microsoft.com/v1.0/users/$UserId" -tenantid $TenantFilter -type PATCH -body '{"accountEnabled":false}'
                & $Add 'Sign-in' 'Success' 'Blocked sign-in to the mailbox account.'
            } else { & $Add 'Sign-in' 'Info' 'Sign-in to the mailbox account is already blocked.' }
        } catch { & $Add 'Sign-in' 'Error' "Couldn't block sign-in: $(& $Err $_)" }
    }

    # ------------------------------------------------------------------ Regional settings
    try {
        $Regional = & $Exo 'Get-MailboxRegionalConfiguration' @{ Identity = $Address } $Address | Select-Object -First 1
        if ("$($Regional.Language)" -ne $Language -or "$($Regional.TimeZone)" -ne $TimeZone) {
            $Params = @{ Identity = $Address; Language = $Language; TimeZone = $TimeZone; LocalizeDefaultFolderName = $true }
            if ($Language -eq 'en-GB') { $Params.DateFormat = 'dd/MM/yyyy'; $Params.TimeFormat = 'HH:mm' }
            $null = & $Exo 'Set-MailboxRegionalConfiguration' $Params $Address
            & $Add 'Regional settings' 'Success' "Set the language to $Language and the time zone to $TimeZone."
        }
    } catch { & $Add 'Regional settings' 'Warning' "Couldn't set the language and time zone: $(& $Err $_)" }

    # ------------------------------------------------------------------ Who has access
    $Status = Get-CIPPSharedMailboxStatus -TenantFilter $TenantFilter -Identity $Address
    $PeopleKeys = @($People | Where-Object { $_ } | ForEach-Object { "$_".Trim().ToLowerInvariant() })
    $Trustees = @($PeopleKeys)
    if ($A.grantVia -eq 'group') {
        if (-not $GroupName) { $GroupName = "$($Defaults.accessGroupPrefix)$((($Address -split '@')[0]))" }
        $Group = try { & $Exo 'Get-DistributionGroup' @{ Identity = $GroupName } | Select-Object -First 1 } catch { $null }
        if (-not $Group) {
            try {
                $Domain = ($Address -split '@')[1]
                $GroupAlias = ($GroupName -replace '[^A-Za-z0-9._-]', '').ToLowerInvariant()
                $Group = & $Exo 'New-DistributionGroup' @{ Name = $GroupName; DisplayName = $GroupName; Type = 'Security'; Alias = $GroupAlias; PrimarySmtpAddress = "$GroupAlias@$Domain"; MemberJoinRestriction = 'Closed'; MemberDepartRestriction = 'Closed'; RequireSenderAuthenticationEnabled = $true }
                $null = & $Exo 'Set-DistributionGroup' @{ Identity = "$GroupAlias@$Domain"; HiddenFromAddressListsEnabled = $true; BypassSecurityGroupManagerCheck = $true }
                & $Add 'Access group' 'Success' "Created the access group $GroupName."
            } catch { & $Add 'Access group' 'Error' "Couldn't create the access group $($GroupName): $(& $Err $_)" }
        }
        if ($Group) {
            $GroupAddress = "$($Group.PrimarySmtpAddress)"
            $Members = @(try { & $Exo 'Get-DistributionGroupMember' @{ Identity = $GroupAddress; ResultSize = 'Unlimited' } } catch { @() })
            $MemberKeys = @($Members | ForEach-Object { "$($_.PrimarySmtpAddress)".ToLowerInvariant(); "$($_.WindowsLiveID)".ToLowerInvariant() } | Where-Object { $_ })
            foreach ($P in $PeopleKeys | Where-Object { $MemberKeys -notcontains $_ }) {
                try { $null = & $Exo 'Add-DistributionGroupMember' @{ Identity = $GroupAddress; Member = $P; BypassSecurityGroupManagerCheck = $true }; & $Add 'Access group' 'Success' "Added $P to $GroupName." }
                catch { & $Add 'Access group' 'Error' "Couldn't add $P to $($GroupName): $(& $Err $_)" }
            }
            if ($RemoveOthers) {
                foreach ($M in $Members | Where-Object { $PeopleKeys -notcontains "$($_.PrimarySmtpAddress)".ToLowerInvariant() -and $PeopleKeys -notcontains "$($_.WindowsLiveID)".ToLowerInvariant() }) {
                    try { $null = & $Exo 'Remove-DistributionGroupMember' @{ Identity = $GroupAddress; Member = "$($M.PrimarySmtpAddress)"; BypassSecurityGroupManagerCheck = $true; Confirm = $false }; & $Add 'Access group' 'Success' "Removed $($M.DisplayName) from $GroupName." }
                    catch { & $Add 'Access group' 'Error' "Couldn't remove $($M.DisplayName) from $($GroupName): $(& $Err $_)" }
                }
            }
            $Trustees = @($GroupAddress.ToLowerInvariant())
        } else {
            $Trustees = @()
        }
    }

    # A holder matches a person by any of its names (sign-in name, address, alias, display name).
    $Holds = { param($List, [string]$Key) [bool](@($List) | Where-Object { @($_.Keys) -contains $Key -or "$($_.Address)".ToLowerInvariant() -eq $Key }) }
    $Perm = {
        param($Level, $Action, $Who, $AutoMap = $true)
        $R = Set-CIPPMailboxPermission -UserId $Address -AccessUser $Who -PermissionLevel $Level -Action $Action -AutoMap $AutoMap -TenantFilter $TenantFilter -APIName $APIName -Headers $Headers
        $Label = @{ FullAccess = 'Full Access'; SendAs = 'Send As'; SendOnBehalf = 'Send on behalf' }[$Level]
        if ("$R" -match '^Failed') { & $Add $Label 'Error' "$R" } else { & $Add $Label 'Success' "$(if ($Action -eq 'Add') { 'Gave' } else { 'Removed' }) $Label $(if ($Action -eq 'Add') { 'to' } else { 'from' }) $Who$(if ($Level -eq 'FullAccess' -and $Action -eq 'Add') { if ($AutoMap) { ', shown in Outlook automatically' } else { ', not added to Outlook automatically' } })." }
    }

    $AutoMap = $A.outlook -eq 'automap' -and $A.grantVia -eq 'people'
    $Unlisted = { param($List) @($List | Where-Object { $H = $_; $_.Address -and -not ($Trustees | Where-Object { @($H.Keys) -contains $_ -or "$($H.Address)".ToLowerInvariant() -eq $_ }) }) }

    # Full Access
    foreach ($T in $Trustees) {
        if (& $Holds $Status.FullAccess $T) {
            if ($ReapplyAccess) { & $Perm 'FullAccess' 'Remove' $T; & $Perm 'FullAccess' 'Add' $T $AutoMap }
        } else { & $Perm 'FullAccess' 'Add' $T $AutoMap }
    }
    if ($RemoveOthers) { foreach ($O in & $Unlisted $Status.FullAccess) { & $Perm 'FullAccess' 'Remove' $O.Address } }

    # Sending
    foreach ($T in $Trustees) {
        $HasAs = & $Holds $Status.SendAs $T
        $HasBehalf = & $Holds $Status.SendOnBehalf $T
        switch ($A.send) {
            'sendAs' { if (-not $HasAs) { & $Perm 'SendAs' 'Add' $T }; if ($HasBehalf) { & $Perm 'SendOnBehalf' 'Remove' $T } }
            'sendOnBehalf' { if (-not $HasBehalf) { & $Perm 'SendOnBehalf' 'Add' $T }; if ($HasAs) { & $Perm 'SendAs' 'Remove' $T } }
            'none' { if ($HasAs) { & $Perm 'SendAs' 'Remove' $T }; if ($HasBehalf) { & $Perm 'SendOnBehalf' 'Remove' $T } }
        }
    }
    if ($RemoveOthers) {
        foreach ($O in & $Unlisted $Status.SendAs) { & $Perm 'SendAs' 'Remove' $O.Address }
        foreach ($O in & $Unlisted $Status.SendOnBehalf) { & $Perm 'SendOnBehalf' 'Remove' $O.Address }
    }
    if ($Trustees.Count -eq 0 -and -not $RemoveOthers) { & $Add 'Access' 'Info' 'No people were given, so access was left as it is.' }

    # ------------------------------------------------------------------ Mailbox settings
    $Settings = @{}
    $CopySent = $A.sentItems -eq 'shared'
    if ($Status.MessageCopySentAs -ne $CopySent) { $Settings.MessageCopyForSentAsEnabled = $CopySent }
    if ($Status.MessageCopySendOnBehalf -ne $CopySent) { $Settings.MessageCopyForSendOnBehalfEnabled = $CopySent }
    $Hide = $A.visibility -eq 'hidden'
    if ($Status.Hidden -ne $Hide) { $Settings.HiddenFromAddressListsEnabled = $Hide }
    $Internal = $A.external -eq 'internal'
    if ($Status.InternalOnly -ne $Internal) { $Settings.RequireSenderAuthenticationEnabled = $Internal }
    if ($Settings.Count) {
        try {
            $null = & $Exo 'Set-Mailbox' (@{ Identity = $Address } + $Settings) $Address
            $Done = @()
            if ($Settings.ContainsKey('MessageCopyForSentAsEnabled') -or $Settings.ContainsKey('MessageCopyForSendOnBehalfEnabled')) { $Done += if ($CopySent) { 'sent emails are copied to the shared mailbox' } else { 'sent emails stay only in the sender''s Sent Items' } }
            if ($Settings.ContainsKey('HiddenFromAddressListsEnabled')) { $Done += if ($Hide) { 'hidden from the address book' } else { 'shown in the address book' } }
            if ($Settings.ContainsKey('RequireSenderAuthenticationEnabled')) { $Done += if ($Internal) { 'only accepts email from inside the business' } else { 'accepts email from anyone' } }
            & $Add 'Settings' 'Success' "Set the mailbox so it $($Done -join '; ')."
        } catch { & $Add 'Settings' 'Error' "Couldn't change the mailbox settings: $(& $Err $_)" }
    } else { & $Add 'Settings' 'Info' 'Sent copies, address book and who can email it were already as chosen.' }

    # ------------------------------------------------------------------ Signature rule
    $RuleName = Get-CIPPSharedMailboxSignatureRuleName -Address $Address
    if ($A.signature -eq 'rule') {
        $Html = "$SignatureHtml".Trim()
        try {
            if ($Status.SignatureRule) {
                if ($Html) { $null = & $Exo 'Set-TransportRule' @{ Identity = $RuleName; ApplyHtmlDisclaimerText = $Html }; & $Add 'Signature' 'Success' 'Updated the signature added to emails from the mailbox.' }
                else { & $Add 'Signature' 'Info' 'The signature rule is already in place.' }
            } elseif ($Html) {
                $null = & $Exo 'New-TransportRule' @{ Name = $RuleName; From = $Address; ApplyHtmlDisclaimerLocation = 'Append'; ApplyHtmlDisclaimerText = $Html; ApplyHtmlDisclaimerFallbackAction = 'Wrap'; Comments = 'Adds the shared mailbox signature (CIPP shared mailbox add-on).' }
                & $Add 'Signature' 'Success' 'Added a rule that puts the signature on every email sent from the mailbox.'
            } else { & $Add 'Signature' 'Warning' 'No signature was given, so the signature rule wasn''t made.' }
        } catch { & $Add 'Signature' 'Error' "Couldn't set up the signature rule: $(& $Err $_)" }
    } elseif ($Status.SignatureRule) {
        try { $null = & $Exo 'Remove-TransportRule' @{ Identity = $RuleName; Confirm = $false }; & $Add 'Signature' 'Success' 'Removed the rule that added a signature, as the signature is now handled another way.' }
        catch { & $Add 'Signature' 'Error' "Couldn't remove the signature rule: $(& $Err $_)" }
    }

    # ------------------------------------------------------------------ Size, licence and archive
    if ($A.size -eq 'licensed') {
        if ($Status.Licensed -eq $false) { & $Add 'Licence' 'Warning' "Assign an Exchange Online Plan 1 (or higher) licence to $Address for 100 GB, an archive and legal hold." }
        if ($EnableArchive) {
            if ($Status.ArchiveActive) { & $Add 'Archive' 'Info' 'The archive is already on.' }
            elseif ($Status.Licensed) {
                try { $null = & $Exo 'Enable-Mailbox' @{ Identity = $Address; Archive = $true } $Address; & $Add 'Archive' 'Success' 'Turned on the archive mailbox.' }
                catch { & $Add 'Archive' 'Error' "Couldn't turn on the archive: $(& $Err $_)" }
            } else { & $Add 'Archive' 'Warning' 'The archive needs a licence; turn it on again once the licence is assigned.' }
        }
    } elseif ($Status.SizeBytes -gt 45GB) {
        & $Add 'Size' 'Warning' "The mailbox holds $([math]::Round($Status.SizeBytes / 1GB, 1)) GB; unlicensed shared mailboxes stop at 50 GB."
    }

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Set up shared mailbox $Address ($(@($Steps | Where-Object Status -eq 'Error').Count) errors)" -Sev Info
    [pscustomobject]@{ Address = $Address; Steps = @($Steps) }
}
