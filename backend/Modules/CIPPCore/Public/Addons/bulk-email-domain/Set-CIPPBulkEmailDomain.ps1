function Set-CIPPBulkEmailDomain {
    <#
    .SYNOPSIS
        Gives a set of users an email address on a domain, as an alias or as their new primary address.

    .DESCRIPTION
        For each user's mailbox, the address is <name>@<Domain>, where <name> is the part before the @ of
        their current primary email address (NameFrom email) or of their sign-in name (NameFrom upn).

          Mode alias    adds the address as an alias (smtp:).
          Mode primary  adds it if needed and makes it the primary address (SMTP:); the old primary
                        address stays on as an alias, so mail to it still arrives.

        The proxy addresses are changed the same way as the user page's Add Alias and Make Primary
        (Invoke-EditUserAliases), with one Set-Mailbox per user, sent together in an Exchange batch.

        Skipped, with the reason: users without a mailbox, mailboxes synced from on-premises Active
        Directory (change them there), an address another recipient already has, and users that already
        have the address (as an alias, or as their primary address in primary mode).

        The domain must be a verified domain of the tenant. Sign-in names (UPNs) are not changed.

    .OUTPUTS
        One object per user: Id, Name, Address, Status (Changed, Skipped or Failed), Message.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$Domain,
        [ValidateSet('alias', 'primary')][string]$Mode = 'alias',
        [ValidateSet('email', 'upn')][string]$NameFrom = 'email',
        [Parameter(Mandatory)][object[]]$Users,
        $Headers,
        [string]$APIName = 'Bulk email domain'
    )

    $Domain = $Domain.Trim().ToLowerInvariant()
    $Verified = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/domains?$select=id,isVerified' -tenantid $TenantFilter |
            Where-Object { $_.isVerified } | ForEach-Object { "$($_.id)".ToLowerInvariant() })
    if ($Verified -notcontains $Domain) { throw "$Domain isn't a verified domain in this tenant." }

    $Mailboxes = @{}
    foreach ($M in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Mailbox' -cmdParams @{ ResultSize = 'Unlimited' } -Select 'DisplayName,UserPrincipalName,PrimarySmtpAddress,EmailAddresses,ExternalDirectoryObjectId,IsDirSynced,Guid' -useSystemMailbox $true)) {
        if ($M.ExternalDirectoryObjectId) { $Mailboxes["$($M.ExternalDirectoryObjectId)".ToLowerInvariant()] = $M }
    }
    # Every address in the tenant and who has it, to catch clashes before Exchange refuses them.
    $Owners = @{}
    foreach ($R in @(New-ExoRequest -tenantid $TenantFilter -cmdlet 'Get-Recipient' -cmdParams @{ ResultSize = 'Unlimited' } -Select 'DisplayName,EmailAddresses,ExternalDirectoryObjectId' -useSystemMailbox $true)) {
        foreach ($Proxy in @($R.EmailAddresses)) {
            if ("$Proxy" -match '^smtp:(.+)$') { $Owners[$Matches[1].ToLowerInvariant()] = $R }
        }
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Requests = [System.Collections.Generic.List[object]]::new()
    $Pending = @{}
    $Planned = @{}
    $Result = { param($U, $Name, $Address, $Status, $Message) $Results.Add([pscustomobject]@{ Id = "$($U.id)"; Name = $Name; Address = $Address; Status = $Status; Message = $Message }) }

    foreach ($U in $Users) {
        $Id = "$($U.id)".ToLowerInvariant()
        $Mailbox = $Mailboxes[$Id]
        $Name = if ($Mailbox.DisplayName) { "$($Mailbox.DisplayName)" } elseif ($U.displayName) { "$($U.displayName)" } else { "$($U.userPrincipalName)" }
        if (-not $Mailbox) { & $Result $U $Name $null 'Skipped' 'No mailbox, so no email address to change.'; continue }
        if ($Mailbox.IsDirSynced) { & $Result $U $Name $null 'Skipped' 'Synced from on-premises Active Directory: change its addresses there.'; continue }

        $Source = if ($NameFrom -eq 'upn') { "$($Mailbox.UserPrincipalName)" } else { "$($Mailbox.PrimarySmtpAddress)" }
        $LocalPart = ($Source -split '@')[0]
        if (-not $LocalPart) { & $Result $U $Name $null 'Skipped' "Couldn't work out the name before the @."; continue }
        $Address = "$LocalPart@$Domain"
        $Key = $Address.ToLowerInvariant()

        $Current = @($Mailbox.EmailAddresses | ForEach-Object { "$_" })
        $Has = [bool]($Current | Where-Object { $_.ToLowerInvariant() -eq "smtp:$Key" })
        $IsPrimary = "$($Mailbox.PrimarySmtpAddress)".ToLowerInvariant() -eq $Key
        $Owner = $Owners[$Key]
        if ($Owner -and "$($Owner.ExternalDirectoryObjectId)".ToLowerInvariant() -ne $Id) { & $Result $U $Name $Address 'Skipped' "$Address already belongs to $($Owner.DisplayName)."; continue }
        if ($Planned.ContainsKey($Key)) { & $Result $U $Name $Address 'Skipped' "$Address would also be given to $($Planned[$Key]); change one of them by hand."; continue }
        if ($Mode -eq 'alias' -and $Has) { & $Result $U $Name $Address 'Skipped' "Already has $Address."; continue }
        if ($Mode -eq 'primary' -and $IsPrimary) { & $Result $U $Name $Address 'Skipped' "$Address is already the primary address."; continue }

        # Build the new list the same way as Invoke-EditUserAliases.
        $New = @($Current | Where-Object { $_.ToLowerInvariant() -ne "smtp:$Key" })
        if ($Mode -eq 'primary') {
            $New = @("SMTP:$Address") + @($New | ForEach-Object { if ($_ -cmatch '^SMTP:') { 'smtp:' + $_.Substring(5) } else { $_ } })
        } else {
            $New = $New + @("smtp:$Address")
        }
        $Planned[$Key] = $Name
        $Guid = [guid]::NewGuid().ToString()
        $Pending[$Guid] = [pscustomobject]@{ User = $U; Name = $Name; Address = $Address; OldPrimary = "$($Mailbox.PrimarySmtpAddress)"; Had = $Has }
        $Requests.Add(@{ OperationGuid = $Guid; CmdletInput = @{ CmdletName = 'Set-Mailbox'; Parameters = @{ Identity = "$($Mailbox.Guid)"; EmailAddresses = $New } } })
    }

    if ($Requests.Count -gt 0) {
        $Done = @(New-ExoBulkRequest -tenantid $TenantFilter -cmdletArray @($Requests) -useSystemMailbox $true)
        $Errors = @{}
        foreach ($D in $Done) { if ($D.OperationGuid -and $D.error) { $Errors[$D.OperationGuid] = "$($D.error)" } }
        foreach ($Guid in $Pending.Keys) {
            $P = $Pending[$Guid]
            if ($Errors.ContainsKey($Guid)) {
                & $Result $P.User $P.Name $P.Address 'Failed' "Couldn't change the addresses: $(Get-NormalizedError -Message $Errors[$Guid])"
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Failed to give $($P.Name) $($P.Address): $($Errors[$Guid])" -Sev Error
            } elseif ($Mode -eq 'primary') {
                & $Result $P.User $P.Name $P.Address 'Changed' "$($P.Address) is now the primary address$(if (-not $P.Had) { ' (added)' }); $($P.OldPrimary) stays as an alias."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Set primary address of $($P.Name) to $($P.Address) (was $($P.OldPrimary))" -Sev Info
            } else {
                & $Result $P.User $P.Name $P.Address 'Changed' "Added $($P.Address) as an alias."
                Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Added alias $($P.Address) to $($P.Name)" -Sev Info
            }
        }
    }
    # In the order the users were given.
    $Order = @{}; $i = 0; foreach ($U in $Users) { $Order["$($U.id)"] = $i++ }
    @($Results | Sort-Object { $Order[$_.Id] })
}
