function New-CIPPPasswordHandover {
    <#
    .SYNOPSIS
        Resets a user's password and puts the new one behind a Password Pusher link that expires after
        a number of days or views, then writes the message to send the customer.

    .DESCRIPTION
        Checks the Password Pusher server is set up before touching the password, so a missing setup
        never leaves a reset password with no way to send it. If the link can't be made after the
        reset, the password is returned instead, with a warning.
        Directory-synced users are reset through password writeback, which always asks for a new
        password at next sign-in.

    .OUTPUTS
        Results for CippApiResults: the link, the message to send (subject and body), or a warning.

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

    # The server first: no reset without a way to hand the password over.
    $Connection = Get-CIPPPasswordHandoverConnection

    $User = New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($UserID)?`$select=id,displayName,userPrincipalName,onPremisesSyncEnabled" -noPagination $true -tenantid $TenantFilter
    $Upn = if ($User.userPrincipalName) { $User.userPrincipalName } else { $UserID }
    $Name = if ($User.displayName) { $User.displayName } elseif ($DisplayName) { $DisplayName } else { $Upn }
    $Synced = $User.onPremisesSyncEnabled -eq $true

    $Password = New-passwordString
    if (-not $PSCmdlet.ShouldProcess($Upn, 'Reset the password and make a link')) { return }
    if ($Synced) {
        $Body = @{ newPassword = $Password } | ConvertTo-Json -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/beta/users/$($User.id ?? $UserID)/authentication/methods/28c10230-6103-485e-b985-444c60001490/resetPassword" -tenantid $TenantFilter -type POST -body $Body
    } else {
        $Body = @{ passwordProfile = @{ forceChangePasswordNextSignIn = $MustChangeNext; password = $Password } } | ConvertTo-Json -Compress
        $null = New-GraphPostRequest -uri "https://graph.microsoft.com/v1.0/users/$($User.id ?? $UserID)" -tenantid $TenantFilter -type PATCH -body $Body
    }
    $ResetText = if ($Synced) {
        "Sent a password reset for $Name ($Upn) through password writeback. It is applied on the local server shortly and they must choose a new password when they sign in."
    } else {
        "Reset the password for $Name ($Upn)$(if ($MustChangeNext) { '; they must choose a new one when they sign in' })."
    }

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
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Reset the password for $Upn but couldn't make the Password Pusher link: $($ErrorMessage.NormalizedError)" -Sev 'Warning' -LogData $ErrorMessage
        return @(
            [pscustomobject]@{
                resultText = "$ResetText The link couldn't be made ($($ErrorMessage.NormalizedError)), so here is the new password instead. Send it to the customer another safe way."
                copyField  = $Password
                state      = 'warning'
            }
        )
    }

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
