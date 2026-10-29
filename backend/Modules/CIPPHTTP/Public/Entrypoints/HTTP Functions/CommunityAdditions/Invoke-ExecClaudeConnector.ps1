function Invoke-ExecClaudeConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.ReadWrite
    .DESCRIPTION
        Community Additions > Standard Processes > Claude for Microsoft 365. Action AddApps adds Anthropic's two Claude apps to the tenant (tenantFilter). Action Apply (after a Global Administrator has approved Microsoft's consent page for both) limits Claude to the chosen Users: through the access group GroupName (default SG-Claude-Users) or, with AssignUsersDirectly, user by user. LockUserConsent also stops users approving apps themselves and turns on admin consent requests. RemoveOtherDirect removes direct assignments for people not in the group. Apply and Action Access (access only) also take ReadAreas (what Claude can read for everyone: mail, calendar, files, teams, meetings), TenantLevel (access level for everyone: read, drafts, assistant, full) and PeopleLevels (extra access for individual people: [{ User, Level }]). See Set-CIPPClaudeConnector and Config/ClaudeConnectorAccess.json.
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
    if ($Action -notin @('AddApps', 'Apply', 'Access')) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Action must be AddApps, Apply or Access.') }

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

    # Access options (Apply and Access).
    $Config = Get-CIPPClaudeConnectorAccessConfig
    $LevelIds = @($Config.levels | ForEach-Object { $_.id })
    $AreaIds = @($Config.readAreas | ForEach-Object { $_.id })
    $IsUserKey = { param($V) $V -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$' -or $V -match '^[^@\s/\\?#]+@[^@\s/\\?#]+$' }
    $AccessArgs = @{}
    if ($null -ne $Body.ReadAreas) {
        $Areas = @(@($Body.ReadAreas) | ForEach-Object { "$($_.value ?? $_)" } | Where-Object { $_ })
        $BadAreas = @($Areas | Where-Object { $AreaIds -notcontains $_ })
        if ($BadAreas.Count -gt 0) { return (& $Respond ([HttpStatusCode]::BadRequest) "Unknown read area: $($BadAreas -join ', ')") }
        if ($Areas.Count -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose at least one thing Claude can read.') }
        $AccessArgs.ReadAreas = $Areas
    }
    $TenantLevel = "$($Body.TenantLevel.value ?? $Body.TenantLevel)"
    if ($TenantLevel) {
        if ($LevelIds -notcontains $TenantLevel) { return (& $Respond ([HttpStatusCode]::BadRequest) "Unknown access level: $TenantLevel") }
        $AccessArgs.TenantLevel = $TenantLevel
    }
    $People = @(@($Body.PeopleLevels) | Where-Object { $_ } | ForEach-Object {
            [pscustomobject]@{ User = "$($_.User.value ?? $_.User)".Trim(); Level = "$($_.Level.value ?? $_.Level)" }
        } | Where-Object { $_.User })
    if ($People.Count -gt 200) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Set extra access for 200 people or fewer at a time.') }
    foreach ($P in $People) {
        if (-not (& $IsUserKey $P.User)) { return (& $Respond ([HttpStatusCode]::BadRequest) "Not a user id or sign-in name: $($P.User)") }
        if ($LevelIds -notcontains $P.Level) { return (& $Respond ([HttpStatusCode]::BadRequest) "Unknown access level for $($P.User): $($P.Level)") }
    }
    if ($People.Count -gt 0) { $AccessArgs.PeopleLevels = $People }
    if ($Action -eq 'Access' -and $AccessArgs.Count -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Nothing to change: give ReadAreas, TenantLevel or PeopleLevels.') }

    try {
        $Steps = Set-CIPPClaudeConnector @AccessArgs -TenantFilter $TenantFilter -Action $Action -Users $Users -GroupName $GroupName `
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
