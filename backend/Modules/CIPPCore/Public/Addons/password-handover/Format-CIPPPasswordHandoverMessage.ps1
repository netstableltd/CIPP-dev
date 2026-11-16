function Format-CIPPPasswordHandoverMessage {
    <#
    .SYNOPSIS
        Fills in the hand-over message (or subject) for one user: {displayName}, {userPrincipalName}, {link},
        {views}, {expiryDate}, {signInUrl}, {passphraseLine} and {mustChangeLine}. Unknown placeholders are left as they are.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Settings,
        [string]$DisplayName,
        [string]$UserPrincipalName,
        [string]$Link,
        [datetime]$ExpiresOn,
        [bool]$MustChange,
        [bool]$Synced
    )

    $PassphraseLine = if ($Settings.passphrase -eq 'email') { ' When the page asks for a passphrase, enter the email address the password is for.' } else { '' }
    $MustChangeLine = if ($MustChange -or $Synced) { ' You will be asked to choose your own password straight away.' } else { '' }
    $Values = @{
        displayName       = $DisplayName
        userPrincipalName = $UserPrincipalName
        link              = $Link
        views             = "$($Settings.expireAfterViews)"
        expiryDate        = $ExpiresOn.ToString('dddd d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))
        signInUrl         = $Settings.signInUrl
        passphraseLine    = $PassphraseLine
        mustChangeLine    = $MustChangeLine
    }
    [regex]::Replace($Template, '\{([A-Za-z]+)\}', {
            param($m)
            $Key = $m.Groups[1].Value
            if ($Values.ContainsKey($Key)) { "$($Values[$Key])" } else { $m.Value }
        })
}
