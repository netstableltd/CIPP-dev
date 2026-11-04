function Invoke-ExecBulkEmailDomain {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.ReadWrite
    .DESCRIPTION
        Identity Management > Users > Edit Properties (add-on bulk-email-domain): gives the selected users (Users: [{ id, userPrincipalName }], one tenant: tenantFilter) an email address on a verified domain (Domain). Mode alias adds it as an alias; Mode primary adds it and makes it the primary address, keeping the old primary address as an alias. NameFrom email (default) uses the part before the @ of each user's current email address, NameFrom upn the part of their sign-in name. Sign-in names are not changed. Users without a mailbox, synced from on-premises, or whose new address another recipient already has are skipped with the reason. Returns a line per user.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $B = $Request.Body
    $TenantFilter = "$($B.tenantFilter)"
    $Bad = { param($Text) [HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = @($Text) } } }

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Bad 'Choose users from a single tenant.') }
    $Domain = "$($B.Domain.value ?? $B.Domain)".Trim()
    if ($Domain -notmatch '^[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)+$') { return (& $Bad 'Choose the domain for the new addresses.') }
    $Mode = "$($B.Mode)"
    if ($Mode -notin 'alias', 'primary') { return (& $Bad 'Mode must be alias or primary.') }
    $NameFrom = if ($B.NameFrom) { "$($B.NameFrom)" } else { 'email' }
    if ($NameFrom -notin 'email', 'upn') { return (& $Bad 'NameFrom must be email or upn.') }
    $Users = @($B.Users | Where-Object { "$($_.id)" -match '^[0-9a-fA-F-]{36}$' })
    if ($Users.Count -eq 0) { return (& $Bad 'No users were given.') }
    if ($Users.Count -ne @($B.Users).Count) { return (& $Bad 'Every user needs its id.') }
    if ($Users.Count -gt 1000) { return (& $Bad 'Change up to 1,000 users at a time.') }

    try {
        $Results = Set-CIPPBulkEmailDomain -TenantFilter $TenantFilter -Domain $Domain -Mode $Mode -NameFrom $NameFrom -Users $Users -Headers $Request.Headers -APIName $APIName
        $Count = { param($S) @($Results | Where-Object Status -eq $S).Count }
        $What = if ($Mode -eq 'primary') { "made @$Domain the primary address" } else { "added an @$Domain alias" }
        $Summary = "$($What.Substring(0,1).ToUpper())$($What.Substring(1)) for $(& $Count 'Changed') of $($Users.Count) user$(if ($Users.Count -ne 1) { 's' })$(if (& $Count 'Skipped') { "; $(& $Count 'Skipped') skipped" })$(if (& $Count 'Failed') { "; $(& $Count 'Failed') failed" })."
        $Lines = @($Summary) + @($Results | ForEach-Object { "$($_.Name): $($_.Message)" })
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = $Lines; Users = @($Results) } })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $APIName -tenant $TenantFilter -message "Bulk email domain change failed: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = @("The change failed: $($ErrorMessage.NormalizedError)") } })
    }
}
