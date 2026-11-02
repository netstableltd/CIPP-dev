function Get-CIPPSharedMailboxStatus {
    <#
    .SYNOPSIS
        How a shared mailbox is set up now: who has access and how, the mailbox settings the setup page
        offers, its size and licence, and the answers those settings amount to (Current).

    .DESCRIPTION
        Read-only. Each part is read separately; a part that can't be read is $null and named in Warnings,
        rather than failing the whole status. Whether automapping is on can't be read from Exchange, so
        Current.outlook is always $null.

    .PARAMETER Identity
        The mailbox's address (or any identity Get-Mailbox accepts).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$Identity
    )

    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Try = {
        param([string]$What, [scriptblock]$Script)
        try { & $Script } catch { $Warnings.Add("Couldn't read $($What): $((Get-CippException -Exception $_).NormalizedError)"); $null }
    }

    $Mailbox = try {
        New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ Identity = $Identity } | Select-Object -First 1
    } catch { $null }
    if (-not $Mailbox) {
        return [pscustomobject]@{ Exists = $false; Address = $Identity; Warnings = @() }
    }
    $Address = "$($Mailbox.PrimarySmtpAddress)"
    $Anchor = $Address

    # Who holds a permission: name, address and whether it is a group.
    $RecipientCache = @{}
    $Describe = {
        param([string]$Who)
        if ($RecipientCache.ContainsKey($Who)) { return $RecipientCache[$Who] }
        $R = try { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{ Identity = $Who } -Select 'DisplayName,PrimarySmtpAddress,RecipientTypeDetails,Name,Alias' | Select-Object -First 1 } catch { $null }
        $Info = [pscustomobject]@{
            Name    = if ($R.DisplayName) { "$($R.DisplayName)" } else { $Who }
            Address = if ($R.PrimarySmtpAddress) { "$($R.PrimarySmtpAddress)" } else { $Who }
            IsGroup = "$($R.RecipientTypeDetails)" -match 'Group'
            Keys    = @($Who, $R.DisplayName, $R.PrimarySmtpAddress, $R.Name, $R.Alias) | Where-Object { $_ } | ForEach-Object { "$_".ToLowerInvariant() }
        }
        $RecipientCache[$Who] = $Info
        $Info
    }
    $IsSystem = { param($U) "$U" -match '^(NT AUTHORITY\\|S-1-5-|NAMPR|EURPR|APCPR|\\?Discovery)' }

    $FullAccess = & $Try 'Full Access' {
        @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxPermission' -cmdParams @{ Identity = $Address } -Anchor $Anchor |
            Where-Object { @($_.AccessRights) -contains 'FullAccess' -and -not $_.IsInherited -and -not $_.Deny -and -not (& $IsSystem $_.User) } |
            ForEach-Object { & $Describe "$($_.User)" })
    }
    $SendAs = & $Try 'Send As' {
        @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-RecipientPermission' -cmdParams @{ Identity = $Address } -Anchor $Anchor |
            Where-Object { @($_.AccessRights) -contains 'SendAs' -and -not $_.Deny -and -not (& $IsSystem $_.Trustee) } |
            ForEach-Object { & $Describe "$($_.Trustee)" })
    }
    $SendOnBehalf = @($Mailbox.GrantSendOnBehalfTo | Where-Object { $_ } | ForEach-Object { & $Describe "$_" })

    # An access group: a group holding Full Access.
    $Group = $null
    $GroupHolder = @($FullAccess | Where-Object { $_.IsGroup }) | Select-Object -First 1
    if ($GroupHolder) {
        $Members = & $Try 'the access group''s members' {
            @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-DistributionGroupMember' -cmdParams @{ Identity = $GroupHolder.Address; ResultSize = 'Unlimited' } |
                ForEach-Object { [pscustomobject]@{ Name = "$($_.DisplayName)"; Address = "$($_.PrimarySmtpAddress)" } })
        }
        $Group = [pscustomobject]@{ Name = $GroupHolder.Name; Address = $GroupHolder.Address; Members = @($Members) }
    }

    $UserId = "$($Mailbox.ExternalDirectoryObjectId)"
    $User = if ($UserId) { & $Try 'the sign-in state' { New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserId)?`$select=accountEnabled,onPremisesSyncEnabled" -tenantid $TenantFilter -noPagination $true } } else { $null }
    # The unary comma keeps an empty list as a list (no licences), apart from $null (couldn't read).
    $Licences = if ($UserId) { & $Try 'the licences' { , @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$UserId/licenseDetails" -tenantid $TenantFilter) } } else { $null }
    $ExchangePlans = @($Licences | ForEach-Object { $_.servicePlans } | Where-Object { $_.servicePlanName -match '^EXCHANGE_S_(STANDARD|ENTERPRISE|ARCHIVE)' -and $_.provisioningStatus -ne 'Disabled' })
    $Stats = & $Try 'the mailbox size' { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxStatistics' -cmdParams @{ Identity = $Address } -Anchor $Anchor | Select-Object -First 1 }
    $SizeBytes = if ("$($Stats.TotalItemSize)" -match '\(([\d,\.]+) bytes\)') { [int64]($Matches[1] -replace '[,\.]') } else { $null }
    $Regional = & $Try 'the regional settings' { New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-MailboxRegionalConfiguration' -cmdParams @{ Identity = $Address } -Anchor $Anchor | Select-Object -First 1 }
    $RuleName = Get-CIPPSharedMailboxSignatureRuleName -Address $Address
    $Rule = & $Try 'the signature rule' { @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-TransportRule' -cmdParams @{ ResultSize = 'Unlimited' }) | Where-Object { $_.Name -eq $RuleName } | Select-Object -First 1 }

    $Aliases = @($Mailbox.EmailAddresses | Where-Object { "$_" -cmatch '^smtp:' } | ForEach-Object { "$_".Substring(5) } | Where-Object { $_ -notmatch '\.onmicrosoft\.com$' })
    $Licensed = if ($null -eq $Licences) { $null } else { $ExchangePlans.Count -gt 0 }
    $ArchiveActive = "$($Mailbox.ArchiveStatus)" -eq 'Active' -or ($Mailbox.ArchiveGuid -and "$($Mailbox.ArchiveGuid)" -ne '00000000-0000-0000-0000-000000000000')

    $Send = if (@($SendAs).Count) { 'sendAs' } elseif (@($SendOnBehalf).Count) { 'sendOnBehalf' } elseif (@($FullAccess).Count) { 'none' } else { $null }
    $Current = [ordered]@{
        grantVia   = if ($GroupHolder) { 'group' } elseif (@($FullAccess).Count) { 'people' } else { $null }
        send       = $Send
        outlook    = $null
        sentItems  = if ($Send -eq 'sendOnBehalf') { if ($Mailbox.MessageCopyForSendOnBehalfEnabled) { 'shared' } else { 'personal' } } else { if ($Mailbox.MessageCopyForSentAsEnabled) { 'shared' } else { 'personal' } }
        signature  = if ($Rule) { 'rule' } else { $null }
        visibility = if ($Mailbox.HiddenFromAddressListsEnabled) { 'hidden' } else { 'visible' }
        external   = if ($Mailbox.RequireSenderAuthenticationEnabled) { 'internal' } else { 'anyone' }
        size       = if ($Licensed -or $ArchiveActive) { 'licensed' } elseif ($null -eq $Licensed) { $null } else { 'standard' }
    }

    [pscustomobject]@{
        Exists                  = $true
        IsShared                = "$($Mailbox.RecipientTypeDetails)" -eq 'SharedMailbox'
        RecipientTypeDetails    = "$($Mailbox.RecipientTypeDetails)"
        Address                 = $Address
        DisplayName             = "$($Mailbox.DisplayName)"
        Aliases                 = @($Aliases)
        Id                      = $UserId
        SignInBlocked           = if ($User) { -not [bool]$User.accountEnabled } else { $null }
        SyncedFromOnPremises    = [bool]$User.onPremisesSyncEnabled
        Licensed                = $Licensed
        ExchangePlans           = @($ExchangePlans.servicePlanName | Select-Object -Unique)
        ArchiveActive           = [bool]$ArchiveActive
        SizeBytes               = $SizeBytes
        FullAccess              = @($FullAccess | Select-Object Name, Address, IsGroup, Keys)
        SendAs                  = @($SendAs | Select-Object Name, Address, IsGroup, Keys)
        SendOnBehalf            = @($SendOnBehalf | Select-Object Name, Address, IsGroup, Keys)
        Group                   = $Group
        MessageCopySentAs       = [bool]$Mailbox.MessageCopyForSentAsEnabled
        MessageCopySendOnBehalf = [bool]$Mailbox.MessageCopyForSendOnBehalfEnabled
        Hidden                  = [bool]$Mailbox.HiddenFromAddressListsEnabled
        InternalOnly            = [bool]$Mailbox.RequireSenderAuthenticationEnabled
        Language                = if ($Regional) { "$($Regional.Language)" } else { $null }
        TimeZone                = if ($Regional) { "$($Regional.TimeZone)" } else { $null }
        SignatureRule           = if ($Rule) { [pscustomobject]@{ Name = $Rule.Name; Enabled = "$($Rule.State)" -ne 'Disabled' } } else { $null }
        Current                 = $Current
        Warnings                = @($Warnings)
    }
}
