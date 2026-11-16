function Test-CIPPPasswordHandoverSettings {
    <#
    .SYNOPSIS
        Checks password hand-over settings sent from the page and returns them cleaned up, or throws a
        message the person can act on.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Settings)

    $Days = "$($Settings.expireAfterDays)" -as [int]
    if (-not $Days -or $Days -lt 1 -or $Days -gt 90) { throw 'The link can last from 1 to 90 days.' }
    $Views = "$($Settings.expireAfterViews)" -as [int]
    if (-not $Views -or $Views -lt 1 -or $Views -gt 100) { throw 'The link can be opened from 1 to 100 times.' }
    $Passphrase = "$($Settings.passphrase)".Trim().ToLowerInvariant()
    if ($Passphrase -notin 'email', 'none') { throw 'The passphrase is either the email address or none.' }
    $SignInUrl = "$($Settings.signInUrl)".Trim()
    if ($SignInUrl -notmatch '^https://[^\s<>"]{3,200}$') { throw 'The sign-in address must start with https://.' }
    $Subject = "$($Settings.subject)".Trim()
    if (-not $Subject -or $Subject.Length -gt 200) { throw 'Give a subject of up to 200 characters.' }
    $Message = "$($Settings.message)" -replace "`r`n", "`n"
    if ($Message.Trim().Length -eq 0 -or $Message.Length -gt 5000) { throw 'Give a message of up to 5,000 characters.' }
    if ($Message -notmatch '\{link\}') { throw 'The message must include {link}, or the customer gets no link.' }

    [ordered]@{
        expireAfterDays  = $Days
        expireAfterViews = $Views
        passphrase       = $Passphrase
        retrievalStep    = [bool]($Settings.retrievalStep -eq $true -or "$($Settings.retrievalStep)" -eq 'true')
        mustChange       = [bool]($Settings.mustChange -eq $true -or "$($Settings.mustChange)" -eq 'true')
        signInUrl        = $SignInUrl
        subject          = $Subject
        message          = $Message
    }
}
