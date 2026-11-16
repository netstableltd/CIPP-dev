function Invoke-ExecPasswordHandover {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .DESCRIPTION
        Community Additions > Password hand-over (add-on password-handover): resets the password of one user (ID, their sign-in name or id, in tenantFilter) and returns a Password Pusher link to the new password, plus the message to send the customer. Optional MustChange (choose a new password at next sign-in), ExpireAfterDays (1-90) and ExpireAfterViews (1-100); anything left out uses the add-on's saved settings. Needs Settings > Integrations > Password Pusher to have a server address; nothing is reset without one.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $B = $Request.Body
    $TenantFilter = "$($B.tenantFilter ?? $Request.Query.tenantFilter)"
    $ID = "$($B.ID ?? $Request.Query.ID)".Trim()
    $DisplayName = "$($B.displayName)".Trim()
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $Text } } }

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose a single tenant.') }
    if (-not $ID -or $ID.Length -gt 254 -or $ID -notmatch '^[A-Za-z0-9._%+''@-]+$') { return (& $Bad 'Choose a user.') }
    $Params = @{ TenantFilter = $TenantFilter; UserID = $ID; DisplayName = $DisplayName; Headers = $Request.Headers; APIName = $APIName }
    if ($null -ne $B.MustChange -and "$($B.MustChange)" -ne '') { $Params.MustChange = "$($B.MustChange)" -eq 'true' }
    foreach ($Field in 'ExpireAfterDays', 'ExpireAfterViews') {
        $Raw = "$($B.$Field)".Trim()
        if ($Raw) {
            $Value = $Raw -as [int]
            if (-not $Value) { return (& $Bad "$Field must be a whole number.") }
            $Params[$Field] = $Value
        }
    }

    try {
        $Result = New-CIPPPasswordHandover @Params
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = @($Result) } })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Password hand-over for $ID failed: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "The password wasn't handed over: $($ErrorMessage.NormalizedError)" } })
    }
}
