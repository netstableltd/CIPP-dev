function New-CIPPPasswordHandover {
    <#
    .SYNOPSIS
        Resets a user's password and puts the new one behind a Password Pusher link that expires after
        a number of days or views, then writes the message to send the customer.

    .DESCRIPTION
        The link is made first, with the new password, and the password is reset only once the link
        exists. So if Password Pusher isn't set up or doesn't answer, nothing is reset and the
        password is never shown in plain text. If the reset then fails, the link holds a password
        nobody uses and simply expires.
        Directory-synced users are reset through password writeback, which always asks for a new
        password at next sign-in.

    .OUTPUTS
        Results for CippApiResults: the link and the message to send (subject and body).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$UserID,
        [string]$DisplayName,
        $MustChange,
        [int]$ExpireAfterDays,
        [int]$ExpireAfterViews,
        $Headers,
        [string]$APIName = 'Password hand-over'
    )

    $Settings = Get-CIPPPasswordHandoverSettings
    if ($ExpireAfterDays) { $Settings.expireAfterDays = $ExpireAfterDays }
    if ($ExpireAfterViews) { $Settings.expireAfterViews = $ExpireAfterViews }
    if ($Settings.expireAfterDays -lt 1 -or $Settings.expireAfterDays -gt 90) { throw 'The link can last from 1 to 90 days.' }
    if ($Settings.expireAfterViews -lt 1 -or $Settings.expireAfterViews -gt 100) { throw 'The link can be opened from 1 to 100 times.' }
    $MustChangeNext = if ($null -eq $MustChange -or "$MustChange" -eq '') { [bool]$Settings.mustChange } else { [System.Convert]::ToBoolean("$MustChange") }

    $Connection = Get-CIPPPasswordHandoverConnection -ServerUrl $Settings.serverUrl

    $User = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)?`$select=id,displayName,userPrincipalName,onPremisesSyncEnabled" -noPagination $true -tenantid $TenantFilter
    $Upn = if ($User.userPrincipalName) { $User.userPrincipalName } else { $UserID }
    $Name = if ($User.displayName) { $User.displayName } elseif ($DisplayName) { $DisplayName } else { $Upn }
    $Synced = $User.onPremisesSyncEnabled -eq $true
    if (-not $PSCmdlet.ShouldProcess($Upn, 'Reset the password and make a link')) { return }

    # 1. The link, with the new password in it. Nothing has changed yet if this fails.
    $Password = New-passwordString
    try {
        $Push = @{
            Connection        = $Connection
            Payload           = $Password
            ExpireAfterDays   = $Settings.expireAfterDays
            ExpireAfterViews  = $Settings.expireAfterViews
            RetrievalStep     = [bool]$Settings.retrievalStep
            DeletableByViewer = $false
        }
        if ($Settings.passphrase -eq 'email') { $Push.Passphrase = $Upn }
        if ($Connection.WorkspaceId) { $Push.WorkspaceId = $Connection.WorkspaceId }
        $Link = (New-CIPPPwPush @Push).Link
        if (-not $Link) { throw 'Password Pusher gave no link.' }
    } catch {
        throw "The Password Pusher link couldn't be made, so the password was not reset: $($_.Exception.Message)"
    }

    # 2. The reset.
    if ($Synced) {
        $Body = @{ newPassword = $Password } | ConvertTo-Json -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($User.id ?? $UserID)/authentication/methods/28c10230-6103-485e-b985-444c60001490/resetPassword" -tenantid $TenantFilter -type POST -body $Body
        $ResetText = "Sent a password reset for $Name ($Upn) through password writeback. It is applied on the local server shortly and they must choose a new password when they sign in."
    } else {
        $Body = @{ passwordProfile = @{ forceChangePasswordNextSignIn = $MustChangeNext; password = $Password } } | ConvertTo-Json -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($User.id ?? $UserID)" -tenantid $TenantFilter -type PATCH -body $Body
        $ResetText = "Reset the password for $Name ($Upn)$(if ($MustChangeNext) { '; they must choose a new one when they sign in' })."
    }

    # 3. The message.
    $ExpiresOn = (Get-Date).Date.AddDays($Settings.expireAfterDays)
    $Fill = @{ Settings = $Settings; DisplayName = $Name; UserPrincipalName = $Upn; Link = $Link; ExpiresOn = $ExpiresOn; MustChange = $MustChangeNext; Synced = $Synced }
    $Subject = Format-CIPPPasswordHandoverMessage -Template $Settings.subject @Fill
    $Message = Format-CIPPPasswordHandoverMessage -Template $Settings.message @Fill

    Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Reset the password for $Upn and made a Password Pusher link ($($Settings.expireAfterDays) days, $($Settings.expireAfterViews) views$(if ($Settings.passphrase -eq 'email') { ', email as passphrase' }))." -Sev 'Info'

    $Expiry = $ExpiresOn.ToString('d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))
    @(
        [pscustomobject]@{
            resultText = "$ResetText Password link (opens $($Settings.expireAfterViews) times, until $Expiry$(if ($Settings.passphrase -eq 'email') { "; passphrase: $Upn" })): $Link"
            copyField  = $Link
            state      = 'success'
        }
        [pscustomobject]@{
            resultText = "Message for the customer. Subject: $Subject`n`n$Message"
            copyField  = "$Message"
            state      = 'info'
        }
    )
}
