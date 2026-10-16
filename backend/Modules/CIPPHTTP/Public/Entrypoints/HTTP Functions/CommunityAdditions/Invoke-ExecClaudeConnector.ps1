function Invoke-ExecClaudeConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Community Additions > Standard Processes > Claude for Microsoft 365. Action AddApps adds Anthropic's two Claude apps to the tenant (tenantFilter). Action Apply (after a Global Administrator has approved Microsoft's consent page for both) limits Claude to the chosen Users: through the access group GroupName (default SG-Claude-Users) or, with AssignUsersDirectly, user by user. LockUserConsent also stops users approving apps themselves and turns on admin consent requests. RemoveOtherDirect removes direct assignments for people not in the group. See Set-CIPPClaudeConnector.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body
    $Respond = { param($Code, $Results) [HttpResponseContext]@{ StatusCode = $Code; Body = @{ Results = $Results } } }
    $Bool = { param($V) $V -eq $true -or "$V" -eq 'true' }

    $TenantFilter = "$($Body.tenantFilter.value ?? $Body.tenantFilter)"
    $Action = "$($Body.Action)"
    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose a single tenant.') }
    if ($Action -notin @('AddApps', 'Apply')) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Action must be AddApps or Apply.') }

    $GroupName = "$($Body.GroupName)".Trim()
    if (-not $GroupName) { $GroupName = 'SG-Claude-Users' }
    if ($GroupName -notmatch '^[A-Za-z0-9 _.\-]{1,120}$') { return (& $Respond ([HttpStatusCode]::BadRequest) 'The group name can only use letters, numbers, spaces, dots, dashes and underscores (up to 120).') }

    $Users = @(@($Body.Users) | ForEach-Object { if ($null -ne $_.value) { "$($_.value)" } else { "$_" } } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    if ($Action -eq 'Apply') {
        if ($Users.Count -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose at least one person who can use Claude.') }
        if ($Users.Count -gt 500) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose 500 people or fewer.') }
        $Bad = @($Users | Where-Object { $_ -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -and $_ -notmatch '^[^@\s/\\?#]+@[^@\s/\\?#]+$' })
        if ($Bad.Count -gt 0) { return (& $Respond ([HttpStatusCode]::BadRequest) "Not a user id or sign-in name: $($Bad -join ', ')") }
    }

    try {
        $Steps = Set-CIPPClaudeConnector -TenantFilter $TenantFilter -Action $Action -Users $Users -GroupName $GroupName `
            -AssignUsersDirectly:(& $Bool $Body.AssignUsersDirectly) -LockUserConsent:(& $Bool $Body.LockUserConsent) `
            -RemoveOtherDirect:(& $Bool $Body.RemoveOtherDirect) -Headers $Headers -APIName $APIName
        $Steps = @($Steps)
        $Failed = @($Steps | Where-Object { $_.Status -eq 'Error' }).Count
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::OK
                Body       = @{ Results = $Steps; Success = ($Failed -eq 0) }
            })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Claude connector setup failed: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return (& $Respond ([HttpStatusCode]::InternalServerError) "Claude connector setup failed: $($ErrorMessage.NormalizedError)")
    }
}
