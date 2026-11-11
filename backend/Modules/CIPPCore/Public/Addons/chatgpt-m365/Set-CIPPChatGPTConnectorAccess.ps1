function Set-CIPPChatGPTConnectorAccess {
    <#
    .SYNOPSIS
        Sets what ChatGPT can read and change in Microsoft 365: the read areas and access level for everyone,
        and extra access for individual people.

    .DESCRIPTION
        Works on the Microsoft Graph delegated permission grants of OpenAI's 'ChatGPT' app
        (Config/Addons/chatgpt-m365/ChatGPTConnectorAccess.json has the scopes):

        -ReadAreas      Area ids ChatGPT may read for everyone (mail, calendar, files, teams, meetings, tasks).
                        The scopes of areas not listed are removed from the tenant-wide grant; listed ones are
                        added. Omit to leave as is.
        -TenantLevel    Access level for everyone (read, drafts, assistant, full). The tenant-wide grant's
                        write scopes are set to exactly that level's. Omit to leave as is.
        -PeopleLevels   @(@{ User = id or sign-in name; Level = level id }, ...). Each person gets a per-user
                        grant with the write scopes their level adds on top of everyone's level; a level that
                        adds nothing removes their per-user grant. People not listed are left as they are.

        No tenant-wide grant yet: one is created (this is CIPP giving admin consent) with the scopes that are
        always kept, the chosen read areas and the level's write scopes. Both -ReadAreas and -TenantLevel are
        needed for that, so consent is never wider than what was chosen.

        Approving ChatGPT's own "Review permissions in Microsoft Entra" again adds back every permission for
        the actions turned on in ChatGPT. Run this again afterwards.

    .OUTPUTS
        Steps: Step, Status ('Success' | 'Info' | 'Warning' | 'Error'), Message.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][string]$AppSpId,
        [string[]]$ReadAreas,
        [string]$TenantLevel,
        [object[]]$PeopleLevels = @(),
        $Headers,
        [string]$APIName = 'ChatGPTConnector'
    )

    $Graph = 'https://graph.microsoft.com/v1.0'
    $Config = Get-CIPPChatGPTConnectorAccessConfig
    $Results = [System.Collections.Generic.List[object]]::new()
    $Add = {
        param($Status, $Message)
        $Results.Add([pscustomobject]@{ Step = 'Access'; Status = $Status; Message = $Message })
        $Sev = switch ($Status) { 'Error' { 'Error' } 'Warning' { 'Warning' } default { 'Info' } }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "ChatGPT connector: $Message" -Sev $Sev
    }
    $ErrorText = { param($E) try { (Get-CippException -Exception $E).NormalizedError } catch { "$($E.Exception.Message)" } }
    $LevelOf = { param($Id) $Config.levels | Where-Object { $_.id -eq $Id } | Select-Object -First 1 }
    $Split = { param($S) @("$S" -split '\s+' | Where-Object { $_ }) }
    # Write scopes that also let ChatGPT read an area, for the "reading is off but..." warning.
    $WriteReads = @{}
    foreach ($P in @($Config.writeReads.PSObject.Properties)) { $WriteReads[$P.Name] = "$($P.Value)" }
    $AreaNoun = @{}; foreach ($A in $Config.readAreas) { $AreaNoun[$A.id] = $A.noun }
    $HasReadAreas = $PSBoundParameters.ContainsKey('ReadAreas') -and $null -ne $ReadAreas

    try {
        $GraphSp = @(New-GraphGetRequest -uri "$Graph/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id" -tenantid $TenantFilter) | Select-Object -First 1
        $Grants = @(New-GraphGetRequest -uri "$Graph/oauth2PermissionGrants?`$filter=clientId eq '$AppSpId'" -tenantid $TenantFilter | Where-Object { $_.resourceId -eq $GraphSp.id })
    } catch {
        & $Add 'Error' "Couldn't read the ChatGPT app's permissions: $(& $ErrorText $_)"
        return $Results
    }
    $TenantGrant = $Grants | Where-Object { $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1

    # ------------------------------------------------------------------ everyone: read areas and level
    $Current = if ($TenantGrant) { & $Split $TenantGrant.scope } else { @() }
    $New = [System.Collections.Generic.List[string]]::new()
    foreach ($S in $Current) { $New.Add($S) }
    $Changes = [System.Collections.Generic.List[string]]::new()

    if (-not $TenantGrant) {
        if (-not ($HasReadAreas -and $TenantLevel)) {
            & $Add 'Error' "ChatGPT has no admin consent for Microsoft Graph yet. Choose what it can read and a level for everyone, and save, to give consent for exactly that."
            return $Results
        }
        foreach ($S in @($Config.alwaysKeep)) { $New.Add($S) }
    }

    if ($HasReadAreas) {
        foreach ($Area in $Config.readAreas) {
            if ($ReadAreas -contains $Area.id) {
                $Missing = @($Area.scopes | Where-Object { $New -notcontains $_ })
                foreach ($S in $Missing) { $New.Add($S) }
                if ($Missing.Count -gt 0 -and $TenantGrant) { $Changes.Add("$($Area.label) reading turned on") }
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
        if ($BeforeText -ne $AfterText -and $TenantGrant) { $Changes.Add("level for everyone set to Level $($Level.number): $($Level.name)") }
    }

    $NewScopes = @($New)
    if (-not $TenantGrant) {
        try {
            $Body = @{ clientId = $AppSpId; consentType = 'AllPrincipals'; resourceId = $GraphSp.id; scope = ($NewScopes -join ' ') } | ConvertTo-Json -Compress
            $TenantGrant = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
            $Names = @($Config.readAreas | Where-Object { $ReadAreas -contains $_.id } | ForEach-Object { $_.noun }) -join ', '
            & $Add 'Success' "Gave admin consent for ChatGPT, for everyone: Level $($Level.number): $($Level.name), reading $Names."
        } catch {
            & $Add 'Error' "Couldn't give admin consent for ChatGPT: $(& $ErrorText $_)"
            return $Results
        }
    } elseif ($Changes.Count -gt 0) {
        try {
            $Body = @{ scope = ($NewScopes -join ' ') } | ConvertTo-Json -Compress
            $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants/$($TenantGrant.id)" -tenantid $TenantFilter -type PATCH -body $Body -contentType 'application/json'
            & $Add 'Success' "Everyone: $($Changes -join '; ')."
        } catch {
            & $Add 'Error' "Couldn't change access for everyone: $(& $ErrorText $_)"
            $NewScopes = $Current
        }
    } elseif ($TenantLevel -or $HasReadAreas) {
        $Summary = Get-CIPPChatGPTConnectorScopeSummary -Scopes $NewScopes
        $LevelText = if ($Summary.Level -ne 'custom') { $L = & $LevelOf $Summary.Level; "Level $($L.number): $($L.name)" } else { 'a custom set of permissions' }
        & $Add 'Success' "Everyone already has $LevelText, with the chosen read areas."
    }
    $TenantSummary = Get-CIPPChatGPTConnectorScopeSummary -Scopes $NewScopes
    foreach ($S in $TenantSummary.WriteScopes) {
        $Area = $WriteReads[$S]
        if ($Area -and $TenantSummary.ReadAreas -notcontains $Area) { & $Add 'Warning' "Everyone has $S, which also lets ChatGPT read $($AreaNoun[$Area]) even though that reading is off." }
    }
    if (-not $TenantSummary.ReadAreas -or $TenantSummary.ReadAreas.Count -eq 0) {
        & $Add 'Warning' "ChatGPT can't read anything in Microsoft 365 for most people, so the connectors won't be useful."
    }
    if ($TenantLevel) {
        & $Add 'Info' "In ChatGPT's admin console, match the actions to this level: $($Level.chatgptActions) If ChatGPT asks for a permission that isn't granted, people will see 'Need admin approval'."
    }

    # ------------------------------------------------------------------ individual people
    $People = @($PeopleLevels | Where-Object { $_ })
    if ($People.Count -eq 0) { return $Results }

    # Who can use ChatGPT at all: people assigned to the app directly or through a group.
    $Allowed = [System.Collections.Generic.HashSet[string]]::new()
    try {
        foreach ($A in @(New-GraphGetRequest -uri "$Graph/servicePrincipals/$AppSpId/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter)) {
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
                    & $Add 'Success' "$($Who): removed their separate ChatGPT grant (extra access, or an approval they gave themselves); they now have the same as everyone."
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
                    $Body = @{ clientId = $AppSpId; consentType = 'Principal'; principalId = $U.id; resourceId = $GraphSp.id; scope = $Scope } | ConvertTo-Json -Compress
                    $null = New-GraphPOSTRequest -uri "$Graph/oauth2PermissionGrants" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
                    & $Add 'Success' "$($Who): given Level $($Level.number): $($Level.name) ($($Extra -join ', '))."
                }
                foreach ($S in $Extra) {
                    $Area = $WriteReads[$S]
                    if ($Area -and $TenantSummary.ReadAreas -notcontains $Area) { & $Add 'Warning' "$($Who): $S also lets ChatGPT read their $($AreaNoun[$Area]), even though that reading is off for everyone." }
                }
                & $Add 'Info' "$($Who): ChatGPT only uses Level $($Level.number) if its actions are on for them in ChatGPT. That needs ChatGPT Enterprise or Edu with a role for these people; on ChatGPT Business the actions are the same for everyone."
            }
        } catch { & $Add 'Error' "$($Who): couldn't set Level $($Level.number): $(& $ErrorText $_)" }
        if ($null -ne $Allowed -and -not $Allowed.Contains("$($U.id)")) {
            & $Add 'Warning' "$($Who) isn't one of the people who can use ChatGPT, so this has no effect until they are added."
        }
    }
    $Results
}
