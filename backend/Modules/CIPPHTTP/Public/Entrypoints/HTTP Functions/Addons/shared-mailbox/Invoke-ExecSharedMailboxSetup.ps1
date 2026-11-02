function Invoke-ExecSharedMailboxSetup {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Exchange.Mailbox.ReadWrite
    .DESCRIPTION
        Community Additions > Shared mailbox (add-on shared-mailbox): creates a shared mailbox (New: DisplayName, Address, Aliases) or sets up an existing one (Identity), following the customer's choices (Answers: grantVia people or group, send sendAs/sendOnBehalf/none, outlook automap or account, sentItems shared or personal, signature manual/rule/tool, visibility visible or hidden, external anyone or internal, size standard or licensed; a missing answer takes our recommendation). People are the sign-in names of who needs access; GroupName the access group for grantVia group. SignatureHtml is the signature the mail rule adds (signature rule). EnableArchive turns on the archive (licensed only). BlockSignIn (default true), RemoveOthers (take access from anyone not listed), ReapplyAccess (re-grant Full Access so automapping matches), Language and TimeZone (default en-GB, GMT Standard Time). Safe to run again; returns each step (Step, Status, Message) and the mailbox's status afterwards. See Set-CIPPSharedMailbox.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $B = $Request.Body
    $TenantFilter = "$($B.tenantFilter)"
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $Text } } }
    $EmailPattern = '^[A-Za-z0-9._%+''-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$'

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose a single tenant.') }

    $Identity = "$($B.Identity)".Trim()
    $New = $null
    if ($B.New) {
        $DisplayName = "$($B.New.DisplayName)".Trim()
        $Address = "$($B.New.Address)".Trim()
        if (-not $DisplayName -or $DisplayName.Length -gt 256 -or $DisplayName -match '[\x00-\x1f<>]') { return (& $Bad 'Give the mailbox a name of up to 256 characters.') }
        if ($Address -notmatch $EmailPattern -or $Address.Length -gt 254) { return (& $Bad "'$Address' isn't an email address.") }
        $Aliases = @($B.New.Aliases | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
        foreach ($Al in $Aliases) { if ($Al -notmatch $EmailPattern) { return (& $Bad "'$Al' isn't an email address.") } }
        if ($Aliases.Count -gt 20) { return (& $Bad 'Add up to 20 extra addresses.') }
        $New = @{ DisplayName = $DisplayName; Address = $Address; Aliases = $Aliases }
    } elseif (-not $Identity -or $Identity -notmatch $EmailPattern) {
        return (& $Bad 'Choose a shared mailbox, or give the details of a new one.')
    }

    $People = @($B.People | ForEach-Object { if ($_.value) { "$($_.value)" } else { "$_" } } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($P in $People) { if ($P -notmatch $EmailPattern) { return (& $Bad "'$P' isn't a sign-in name.") } }
    if ($People.Count -gt 200) { return (& $Bad 'Give up to 200 people.') }
    $GroupName = "$($B.GroupName)".Trim()
    if ($GroupName -and $GroupName -notmatch '^[A-Za-z0-9][A-Za-z0-9 ._-]{0,63}$') { return (& $Bad 'The group name can use letters, numbers, spaces, dots, dashes and underscores (up to 64).') }
    $SignatureHtml = "$($B.SignatureHtml)"
    if ($SignatureHtml.Length -gt 10000) { return (& $Bad 'The signature must be under 10,000 characters.') }
    $Language = "$($B.Language)".Trim()
    if ($Language -and $Language -notmatch '^[a-z]{2,3}-[A-Z]{2}$') { return (& $Bad "'$Language' isn't a language like en-GB.") }
    $TimeZone = "$($B.TimeZone)".Trim()
    if ($TimeZone -and $TimeZone -notmatch '^[A-Za-z0-9 ().+-]{1,64}$') { return (& $Bad "'$TimeZone' isn't a time zone name.") }
    try { $Answers = Resolve-CIPPSharedMailboxAnswers -Answers $B.Answers } catch { return (& $Bad $_.Exception.Message) }

    try {
        $Params = @{
            TenantFilter  = $TenantFilter
            People        = $People
            Answers       = $Answers
            GroupName     = $GroupName
            SignatureHtml = $SignatureHtml
            EnableArchive = [bool]($B.EnableArchive -eq $true)
            BlockSignIn   = -not ($B.BlockSignIn -eq $false)
            RemoveOthers  = [bool]($B.RemoveOthers -eq $true)
            ReapplyAccess = [bool]($B.ReapplyAccess -eq $true)
            Language      = $Language
            TimeZone      = $TimeZone
            Headers       = $Request.Headers
            APIName       = $APIName
        }
        if ($New) { $Params.New = $New } else { $Params.Identity = $Identity }
        $Result = Set-CIPPSharedMailbox @Params
        $After = if (@($Result.Steps | Where-Object { $_.Step -eq 'Mailbox' -and $_.Status -eq 'Error' }).Count -eq 0) {
            try { Get-CIPPSharedMailboxStatus -TenantFilter $TenantFilter -Identity $Result.Address } catch { $null }
        }
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = @($Result.Steps); Address = $Result.Address; Status = $After } })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Shared mailbox setup failed: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "The setup failed: $($ErrorMessage.NormalizedError)" } })
    }
}
