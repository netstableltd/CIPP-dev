function Set-CIPPClaudeConnectorAccess {
    <#
    .SYNOPSIS
        Sets what Claude can read and change in Microsoft 365: the read areas and access level for everyone,
        and extra access for individual people.

    .DESCRIPTION
        Works on the Microsoft Graph delegated permission grants of the 'M365 MCP Server for Claude' app
        (Config/ClaudeConnectorAccess.json has the scopes):

        -ReadAreas      Area ids Claude may read for everyone (mail, calendar, files, teams, meetings). The
                        scopes of areas not listed are removed from the tenant-wide grant; listed ones are
                        added back. Omit to leave as is.
        -TenantLevel    Access level for everyone (read, drafts, assistant, full). The tenant-wide grant's
                        write scopes are set to exactly that level's. Omit to leave as is.
        -PeopleLevels   @(@{ User = id or sign-in name; Level = level id }, ...). Each person gets a per-user
                        grant with the write scopes their level adds on top of everyone's level; a level that
                        adds nothing removes their per-user grant. People not listed are left as they are.

        Microsoft's admin consent page approves every permission Anthropic's app asks for, including the
        write ones, so re-running consent undoes a lower level. Run this again afterwards.

    .OUTPUTS
        Steps: Step, Status ('Success' | 'Info' | 'Warning' | 'Error'), Message.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$ServerSpId,
        [string[]]$ReadAreas,
        [string]$TenantLevel,
        [object[]]$PeopleLevels = @(),
        $Headers,
        [string]$APIName = 'ClaudeConnector'
    )

    $Graph = 'https://graph.microsoft.com/v1.0'
    $Config = Get-CIPPClaudeConnectorAccessConfig
    $Results = [System.Collections.Generic.List[object]]::new()
    $Add = {
        param($Status, $Message)
        $Results.Add([pscustomobject]@{ Step = 'Access'; Status = $Status; Message = $Message })
        $Sev = switch ($Status) { 'Error' { 'Error' } 'Warning' { 'Warning' } default { 'Info' } }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Claude connector: $Message" -Sev $Sev
    }
    $ErrorText = { param($E) try { (Get-CippException -Exception $E).NormalizedError } catch { "$($E.Exception.Message)" } }
    $LevelOf = { param($Id) $Config.levels | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
    $Split = { param($S) @("$S" -split '\s+' | Where-Object { $_ }) }
    # Write scopes that also let Claude read an area, for the "reading is off but..." warning.
    $WriteReads = @{ 'Mail.ReadWrite' = 'mail'; 'Calendars.ReadWrite' = 'calendar'; 'Files.ReadWrite.All' = 'files' }
    $AreaNoun = @{}; foreach ($A in $Config.readAreas) { $AreaNoun[$A.id] = $A.noun }

    try {
        $GraphSp = @(New-GraphGetRequest -uri "$Graph/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id" -tenantid $TenantFilter) | Select-Object -First 1
        $Grants = @(New-GraphGetRequest -uri "$Graph/oauth2PermissionGrants?`$filter=clientId eq '$ServerSpId'" -tenantid $TenantFilter | Where-Object { $_.resourceId -eq $GraphSp.id })
    } catch {
        & $Add 'Error' "Couldn't read the Claude app's permissions: $(& $ErrorText $_)"
        return $Results
    }
    $TenantGrant = $Grants | Where-Object { $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1
    if (-not $TenantGrant) {
        & $Add 'Error' "M365 MCP Server for Claude has no admin consent for Microsoft Graph yet, so access can't be set."
        return $Results
    }

    # ------------------------------------------------------------------ everyone: read areas and level
    $Current = & $Split $TenantGrant.scope
    $New = [System.Collections.Generic.List[string]]::new()
    foreach ($S in $Current) { $New.Add($S) }
    $Changes = [System.Collections.Generic.List[string]]::new()

    if ($PSBoundParameters.ContainsKey('ReadAreas') -and $null -ne $ReadAreas) {
        foreach ($Area in $Config.readAreas) {
            if ($ReadAreas -contains $Area.id) {
                $Missing = @($Area.scopes | Where-Object { $New -notcontains $_ })
                foreach ($S in $Missing) { $New.Add($S) }
                if ($Missing.Count -gt 0) { $Changes.Add("$($Area.label) reading turned on") }
            } else {
                $Present = @($Area.scopes | Where-Object { $New -contains $_ })
                foreach ($S in $Present) { [void]$New.Remove($S) }
                if ($Present.Count -gt 0) { $Changes.Add("$($Area.label) reading turned off") }
            }
        }
    }
    if ($TenantLevel) {
        $Level = & $LevelOf $TenantLevel
        $Before = @($Config.writeScopes | Where-Object { $New -contains $_ })
        foreach ($S in $Config.writeScopes) { [void]$New.Remove($S) }
        foreach ($S in @($Level.scopes)) { if ($New -notcontains $S) { $New.Add($S) } }
        $After = @($Level.scopes)
        $BeforeText = (@($Before) | Sort-Object) -join ' '
        $AfterText = (@($After) | Sort-Object) -join ' '
        if ($BeforeText -ne $AfterText) { $Changes.Add("level for everyone set to Level $($Level.number): $($Level.name)") }
    }

    $NewScopes = @($New)
    if ($Changes.Count -gt 0) {
        try {
            $Body = @{ scope = ($NewScopes -join ' ') } | ConvertTo-Json -Compress
            $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants/$($TenantGrant.id)" -tenantid $TenantFilter -type PATCH -body $Body -contentType 'application/json'
            & $Add 'Success' "Everyone: $($Changes -join '; ')."
        } catch {
            & $Add 'Error' "Couldn't change access for everyone: $(& $ErrorText $_)"
            $NewScopes = $Current
        }
    } elseif ($TenantLevel -or $null -ne $ReadAreas) {
        $Summary = Get-CIPPClaudeConnectorScopeSummary -Scopes $NewScopes
        $LevelText = if ($Summary.Level -ne 'custom') { $L = & $LevelOf $Summary.Level; "Level $($L.number): $($L.name)" } else { 'a custom set of permissions' }
        & $Add 'Success' "Everyone already has $LevelText, with the chosen read areas."
    }
    $TenantSummary = Get-CIPPClaudeConnectorScopeSummary -Scopes $NewScopes
    foreach ($S in $TenantSummary.WriteScopes) {
        $Area = $WriteReads[$S]
        if ($Area -and $TenantSummary.ReadAreas -notcontains $Area) { & $Add 'Warning' "Everyone has $S, which also lets Claude read $($AreaNoun[$Area]) even though that reading is off." }
    }
    if (-not $TenantSummary.ReadAreas -or $TenantSummary.ReadAreas.Count -eq 0) {
        & $Add 'Warning' "Claude can't read anything in Microsoft 365 for most people, so the connector won't be useful."
    }

    # ------------------------------------------------------------------ individual people
    $People = @($PeopleLevels | Where-Object { $_ })
    if ($People.Count -eq 0) { return $Results }

    # Who can use Claude at all: people assigned to the server app directly or through a group.
    $Allowed = [System.Collections.Generic.HashSet[string]]::new()
    try {
        foreach ($A in @(New-GraphGetRequest -uri "$Graph/servicePrincipals/$ServerSpId/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter)) {
            if ($A.principalType -eq 'User') { [void]$Allowed.Add("$($A.principalId)") }
            elseif ($A.principalType -eq 'Group') {
                foreach ($M in @(New-GraphGetRequest -uri "$Graph/groups/$($A.principalId)/transitiveMembers?`$select=id&`$top=999" -tenantid $TenantFilter)) { [void]$Allowed.Add("$($M.id)") }
            }
        }
    } catch { $Allowed = $null }

    foreach ($P in $People) {
        $Key = "$($P.User.value ?? $P.User)".Trim()
        $Level = & $LevelOf "$($P.Level.value ?? $P.Level)"
        if (-not $Key -or -not $Level) { & $Add 'Warning' "Skipped an entry without a person or level."; continue }
        try {
            $U = New-GraphGetRequest -uri "$Graph/users/$([System.Uri]::EscapeDataString($Key))?`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter -noPagination $true | Select-Object -First 1
        } catch { $U = $null }
        if (-not $U.id) { & $Add 'Warning' "User not found, skipped: $Key"; continue }
        $Who = $U.userPrincipalName

        $Extra = @($Level.scopes | Where-Object { $NewScopes -notcontains $_ })
        $Existing = $Grants | Where-Object { $_.consentType -eq 'Principal' -and $_.principalId -eq $U.id } | Select-Object -First 1
        try {
            if ($Extra.Count -eq 0) {
                if ($Existing) {
                    $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants/$($Existing.id)" -tenantid $TenantFilter -type DELETE -body '' -contentType 'application/json'
                    & $Add 'Success' "$($Who): removed their extra access; they now have the same as everyone."
                } else {
                    & $Add 'Success' "$($Who): has the same access as everyone, Level $($Level.number) or above."
                }
                $Higher = @($TenantSummary.WriteScopes | Where-Object { @($Level.scopes) -notcontains $_ })
                if ($Higher.Count -gt 0) { & $Add 'Info' "$($Who): everyone already has more than Level $($Level.number), and one person can't have less than everyone." }
            } else {
                # Keep any read scopes a person's grant already had; replace its write scopes.
                $Keep = if ($Existing) { @(& $Split $Existing.scope | Where-Object { $Config.writeScopes -notcontains $_ }) } else { @() }
                $Scope = (@($Keep) + $Extra | Select-Object -Unique) -join ' '
                if ($Existing) {
                    $OldText = (@(& $Split $Existing.scope) | Sort-Object) -join ' '
                    $NewText = (@(& $Split $Scope) | Sort-Object) -join ' '
                    if ($OldText -eq $NewText) {
                        & $Add 'Success' "$($Who): already has Level $($Level.number): $($Level.name)."
                    } else {
                        $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants/$($Existing.id)" -tenantid $TenantFilter -type PATCH -body (@{ scope = $Scope } | ConvertTo-Json -Compress) -contentType 'application/json'
                        & $Add 'Success' "$($Who): changed to Level $($Level.number): $($Level.name) ($($Extra -join ', '))."
                    }
                } else {
                    $Body = @{ clientId = $ServerSpId; consentType = 'Principal'; principalId = $U.id; resourceId = $GraphSp.id; scope = $Scope } | ConvertTo-Json -Compress
                    $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
                    & $Add 'Success' "$($Who): given Level $($Level.number): $($Level.name) ($($Extra -join ', '))."
                }
                foreach ($S in $Extra) {
                    $Area = $WriteReads[$S]
                    if ($Area -and $TenantSummary.ReadAreas -notcontains $Area) { & $Add 'Warning' "$($Who): $S also lets Claude read their $($AreaNoun[$Area]), even though that reading is off for everyone." }
                }
            }
        } catch { & $Add 'Error' "$($Who): couldn't set Level $($Level.number): $(& $ErrorText $_)" }
        if ($null -ne $Allowed -and -not $Allowed.Contains("$($U.id)")) {
            & $Add 'Warning' "$($Who) isn't one of the people who can use Claude, so this has no effect until they are added."
        }
    }
    $Results
}
