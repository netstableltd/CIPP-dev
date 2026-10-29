function Set-CIPPClaudeConnector {
    <#
    .SYNOPSIS
        Sets up Anthropic's Claude connector for Microsoft 365 in a tenant, limited to the people you choose.

    .DESCRIPTION
        The CIPP version of Set-ClaudeM365Connector.ps1 (Community Additions > Standard Processes). Safe to
        re-run: every step checks what is already there first.

        Action AddApps
          1. Adds the two Claude service principals (Get-CIPPClaudeConnectorApps) if they are missing. Both
             must exist before Microsoft's consent page for the client app will work.

        Between the two actions a Global Administrator of the tenant approves Microsoft's admin consent page
        for each app (the consent URLs come from Get-CIPPClaudeConnectorStatus). CIPP can't do this step:
        the permissions are Anthropic's, and only the consent page grants exactly what the app asks for.

        Action Apply (needs consent on both apps)
          2. Finds the listed users.
          3. Group mode (default): creates or reuses the access group and adds the users.
             Direct mode (-AssignUsersDirectly, for tenants without Entra ID P1): skips the group.
          4. Assigns the group (or each user) to both apps, then turns on "Assignment required" on both. The
             order matters: turning it on first would lock everyone out if an assignment failed.
          5. Group mode: removes direct user assignments that the group now covers. Other direct assignments
             are left and reported, unless -RemoveOtherDirect.
          6. -LockUserConsent: turns off user self-consent to apps (left alone if CIPP's "Require admin
             consent" standard already manages it) and turns on admin consent requests, with Global
             Administrators added as reviewers (existing reviewers kept).

          7. Access (also on its own with Action Access): what Claude can read and change, for everyone and
             for individual people. See Set-CIPPClaudeConnectorAccess. Only runs when -ReadAreas,
             -TenantLevel or -PeopleLevels is given.

        Not done (manual): Claude's own Organisation settings > Connectors > Microsoft 365; Conditional Access
        on the two apps; removing individual Graph permissions.

    .OUTPUTS
        A list of steps: Step, Status ('Success' | 'Info' | 'Warning' | 'Error'), Message.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [Parameter(Mandatory)][ValidateSet('AddApps', 'Apply', 'Access')][string]$Action,
        [string[]]$Users = @(),
        [string]$GroupName = 'SG-Claude-Users',
        [switch]$AssignUsersDirectly,
        [switch]$LockUserConsent,
        [switch]$RemoveOtherDirect,
        [string[]]$ReadAreas,
        [string]$TenantLevel,
        [object[]]$PeopleLevels = @(),
        $Headers,
        [string]$APIName = 'ClaudeConnector'
    )

    $GlobalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'
    $DefaultAppRole = '00000000-0000-0000-0000-000000000000'
    $Results = [System.Collections.Generic.List[object]]::new()
    $Add = {
        param($Step, $Status, $Message)
        $Results.Add([pscustomobject]@{ Step = $Step; Status = $Status; Message = $Message })
        $Sev = switch ($Status) { 'Error' { 'Error' } 'Warning' { 'Warning' } default { 'Info' } }
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantFilter -message "Claude connector: $Message" -Sev $Sev
    }
    $ErrorText = { param($E) try { (Get-CippException -Exception $E).NormalizedError } catch { "$($E.Exception.Message)" } }
    $Graph = 'https://graph.microsoft.com/v1.0'

    $Apps = @(Get-CIPPClaudeConnectorApps)
    $Sps = @{}
    foreach ($App in $Apps) {
        try {
            $Sp = @(New-GraphGetRequest -uri "$Graph/servicePrincipals?`$filter=appId eq '$($App.AppId)'&`$select=id,appId,displayName,appRoleAssignmentRequired" -tenantid $TenantFilter) | Select-Object -First 1
            if ($Sp.id) { $Sps[$App.Key] = $Sp }
        } catch {
            & $Add 'Claude apps' 'Error' "Couldn't read $($App.Name): $(& $ErrorText $_)"
            return $Results
        }
    }

    # ------------------------------------------------------------------ 1. service principals
    if ($Action -eq 'AddApps') {
        foreach ($App in $Apps) {
            if ($Sps[$App.Key]) { & $Add 'Claude apps' 'Success' "$($App.Name) is already in the tenant."; continue }
            try {
                $Body = @{ appId = $App.AppId } | ConvertTo-Json -Compress
                $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
                & $Add 'Claude apps' 'Success' "Added $($App.Name)."
            } catch {
                & $Add 'Claude apps' 'Error' "Couldn't add $($App.Name): $(& $ErrorText $_)"
            }
        }
        return $Results
    }

    # ------------------------------------------------------------------ Apply: consent must be in place
    foreach ($App in $Apps) {
        $Sp = $Sps[$App.Key]
        if (-not $Sp) { & $Add 'Consent' 'Error' "$($App.Name) isn't in the tenant yet. Add the Claude apps first."; return $Results }
        try {
            $Grants = @(New-GraphGetRequest -uri "$Graph/oauth2PermissionGrants?`$filter=clientId eq '$($Sp.id)'" -tenantid $TenantFilter)
        } catch { & $Add 'Consent' 'Error' "Couldn't check consent for $($App.Name): $(& $ErrorText $_)"; return $Results }
        if (-not ($Grants | Where-Object { $_.consentType -eq 'AllPrincipals' })) {
            & $Add 'Consent' 'Error' "$($App.Name) doesn't have admin consent yet. A Global Administrator of the tenant needs to approve Microsoft's consent page first."
            return $Results
        }
    }
    & $Add 'Consent' 'Success' 'Both Claude apps have admin consent.'

    $HasReadAreas = $PSBoundParameters.ContainsKey('ReadAreas') -and $null -ne $ReadAreas
    $AccessStep = {
        if (-not ($HasReadAreas -or $TenantLevel -or @($PeopleLevels | Where-Object { $_ }).Count -gt 0)) { return }
        $AccessArgs = @{ TenantFilter = $TenantFilter; ServerSpId = $Sps['Server'].id; PeopleLevels = @($PeopleLevels); Headers = $Headers; APIName = $APIName }
        if ($HasReadAreas) { $AccessArgs.ReadAreas = @($ReadAreas) }
        if ($TenantLevel) { $AccessArgs.TenantLevel = $TenantLevel }
        foreach ($R in @(Set-CIPPClaudeConnectorAccess @AccessArgs)) { $Results.Add($R) }
    }
    if ($Action -eq 'Access') {
        . $AccessStep
        return $Results
    }

    # ------------------------------------------------------------------ 2. users
    $UserObjs = [System.Collections.Generic.List[object]]::new()
    foreach ($U in @($Users | Where-Object { "$_".Trim() } | Select-Object -Unique)) {
        try {
            $Found = New-GraphGetRequest -uri "$Graph/users/$([System.Uri]::EscapeDataString("$U".Trim()))?`$select=id,userPrincipalName,displayName" -tenantid $TenantFilter -noPagination $true | Select-Object -First 1
            if ($Found.id) { $UserObjs.Add($Found) } else { & $Add 'Users' 'Warning' "User not found, skipped: $U" }
        } catch { & $Add 'Users' 'Warning' "User not found, skipped: $U" }
    }
    if ($UserObjs.Count -eq 0) { & $Add 'Users' 'Error' 'None of the chosen users were found, so nothing was changed.'; return $Results }
    & $Add 'Users' 'Success' "Users: $(($UserObjs | ForEach-Object { $_.userPrincipalName }) -join ', ')."

    # ------------------------------------------------------------------ 3. group
    $Group = $null
    $GroupMemberIds = @()
    $NewGroup = $false
    if (-not $AssignUsersDirectly) {
        try {
            $SafeName = ConvertTo-CIPPODataFilterValue -Value $GroupName -Type String
            $Filter = [System.Uri]::EscapeDataString("displayName eq '$SafeName'")
            $Group = @(New-GraphGetRequest -uri "$Graph/groups?`$filter=$Filter&`$select=id,displayName,securityEnabled" -tenantid $TenantFilter) | Select-Object -First 1
            if ($Group.id) {
                & $Add 'Group' 'Success' "Group '$GroupName' already exists."
            } else {
                $Nick = ($GroupName -replace '[^A-Za-z0-9]', '')
                if (-not $Nick) { $Nick = 'ClaudeUsers' }
                $Body = @{
                    displayName     = $GroupName
                    mailEnabled     = $false
                    mailNickname    = $Nick
                    securityEnabled = $true
                    description     = 'Users allowed to use the Claude Microsoft 365 connector'
                } | ConvertTo-Json -Compress
                $Group = New-GraphPOSTRequest -uri "$Graph/groups" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
                $NewGroup = $true
                & $Add 'Group' 'Success' "Created group '$GroupName'."
            }
            $Existing = @(New-GraphGetRequest -uri "$Graph/groups/$($Group.id)/members?`$select=id&`$top=999" -tenantid $TenantFilter | ForEach-Object { $_.id })
            foreach ($U in $UserObjs) {
                if ($Existing -contains $U.id) { & $Add 'Group' 'Success' "$($U.userPrincipalName) is already in the group."; continue }
                $Body = @{ '@odata.id' = "https://graph.microsoft.com/v1.0/directoryObjects/$($U.id)" } | ConvertTo-Json -Compress
                $null = New-GraphPOSTRequest -uri "$Graph/groups/$($Group.id)/members/`$ref" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
                & $Add 'Group' 'Success' "Added $($U.userPrincipalName) to the group."
            }
            $GroupMemberIds = @($Existing) + @($UserObjs | ForEach-Object { $_.id }) | Select-Object -Unique
        } catch {
            & $Add 'Group' 'Error' "Couldn't set up group '$GroupName': $(& $ErrorText $_)"
            return $Results
        }
    }

    # ------------------------------------------------------------------ 4. assign, then require assignment
    $Principals = if ($AssignUsersDirectly) { @($UserObjs | ForEach-Object { [pscustomobject]@{ Id = $_.id; Name = $_.userPrincipalName } }) } else { @([pscustomobject]@{ Id = $Group.id; Name = "group '$GroupName'" }) }
    foreach ($App in $Apps) {
        $Sp = $Sps[$App.Key]
        $Failed = $false
        try {
            $Assigned = @(New-GraphGetRequest -uri "$Graph/servicePrincipals/$($Sp.id)/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter)
        } catch { & $Add 'Assignments' 'Error' "Couldn't read who is assigned to $($App.Name): $(& $ErrorText $_)"; continue }
        foreach ($P in $Principals) {
            if ($Assigned.principalId -contains $P.Id) { & $Add 'Assignments' 'Success' "$($App.Name): $($P.Name) is already assigned."; continue }
            $Body = @{ principalId = $P.Id; resourceId = $Sp.id; appRoleId = $DefaultAppRole } | ConvertTo-Json -Compress
            $Tries = 0
            while ($true) {
                try {
                    $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$($Sp.id)/appRoleAssignedTo" -tenantid $TenantFilter -type POST -body $Body -contentType 'application/json'
                    & $Add 'Assignments' 'Success' "$($App.Name): assigned $($P.Name)."
                    break
                } catch {
                    $Message = & $ErrorText $_
                    $Tries++
                    # A group that was only just created can take a few seconds to be found.
                    if ($NewGroup -and $Tries -lt 4 -and $Message -match 'does not exist|not found|Invalid object identifier') { Start-Sleep -Seconds 5; continue }
                    if ($Message -match 'license|licence|premium') { $Message = "$Message (Assigning a group to an app needs Entra ID P1. Use 'Assign users directly' for this tenant.)" }
                    & $Add 'Assignments' 'Error' "$($App.Name): couldn't assign $($P.Name): $Message"
                    $Failed = $true
                    break
                }
            }
        }
        if ($Failed) {
            & $Add 'Assignments' 'Warning' "$($App.Name): left 'Assignment required' as it was, because an assignment failed."
            continue
        }
        if ($Sp.appRoleAssignmentRequired) { & $Add 'Assignments' 'Success' "$($App.Name): assignment was already required."; continue }
        try {
            $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$($Sp.id)" -tenantid $TenantFilter -type PATCH -body '{"appRoleAssignmentRequired":true}' -contentType 'application/json'
            & $Add 'Assignments' 'Success' "$($App.Name): assignment is now required, so only assigned people can use it."
        } catch { & $Add 'Assignments' 'Error' "$($App.Name): couldn't turn on 'Assignment required': $(& $ErrorText $_)" }
    }

    # ------------------------------------------------------------------ 5. tidy direct assignments
    if (-not $AssignUsersDirectly) {
        foreach ($App in $Apps) {
            $Sp = $Sps[$App.Key]
            try {
                $Direct = @(New-GraphGetRequest -uri "$Graph/servicePrincipals/$($Sp.id)/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter | Where-Object { $_.principalType -eq 'User' })
            } catch { & $Add 'Tidy up' 'Warning' "$($App.Name): couldn't check direct assignments: $(& $ErrorText $_)"; continue }
            foreach ($A in $Direct) {
                $InGroup = $GroupMemberIds -contains $A.principalId
                if ($InGroup -or $RemoveOtherDirect) {
                    try {
                        $null = New-GraphPOSTRequest -uri "$Graph/servicePrincipals/$($Sp.id)/appRoleAssignedTo/$($A.id)" -tenantid $TenantFilter -type DELETE -body '' -contentType 'application/json'
                        & $Add 'Tidy up' 'Success' "$($App.Name): removed the direct assignment for $($A.principalDisplayName)$(if ($InGroup) { ' (covered by the group)' })."
                    } catch { & $Add 'Tidy up' 'Warning' "$($App.Name): couldn't remove the direct assignment for $($A.principalDisplayName): $(& $ErrorText $_)" }
                } else {
                    & $Add 'Tidy up' 'Warning' "$($App.Name): $($A.principalDisplayName) is assigned directly but isn't in '$GroupName', so can still use Claude. Left in place."
                }
            }
        }
    }

    # ------------------------------------------------------------------ 7. access (before consent lock-down)
    . $AccessStep

    # ------------------------------------------------------------------ 6. user consent
    if ($LockUserConsent) {
        try {
            $Auth = New-GraphGetRequest -uri "$Graph/policies/authorizationPolicy" -tenantid $TenantFilter | Select-Object -First 1
            $Assigned = @($Auth.defaultUserRolePermissions.permissionGrantPoliciesAssigned)
            $Self = @($Assigned | Where-Object { "$_" -like 'ManagePermissionGrantsForSelf.*' })
            if ($Self.Count -eq 0) {
                & $Add 'User consent' 'Success' 'Users already need an admin to approve apps.'
            } elseif (-not ($Self | Where-Object { $_ -ne 'ManagePermissionGrantsForSelf.cipp-consent-policy' })) {
                & $Add 'User consent' 'Success' "Left as it is: CIPP's 'Require admin consent for applications' standard already manages user consent."
            } else {
                $Keep = @($Assigned | Where-Object { "$_" -notlike 'ManagePermissionGrantsForSelf.*' })
                $Body = @{ defaultUserRolePermissions = @{ permissionGrantPoliciesAssigned = $Keep } } | ConvertTo-Json -Depth 5 -Compress
                $null = New-GraphPOSTRequest -uri "$Graph/policies/authorizationPolicy" -tenantid $TenantFilter -type PATCH -body $Body -contentType 'application/json'
                & $Add 'User consent' 'Success' 'Users can no longer approve apps themselves. Apps they already approved are not removed (Enterprise apps > Permissions).'
            }
        } catch { & $Add 'User consent' 'Error' "Couldn't change user consent: $(& $ErrorText $_)" }

        try {
            $Policy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $TenantFilter | Select-Object -First 1
            $Reviewers = [System.Collections.Generic.List[object]]::new()
            foreach ($R in @($Policy.reviewers)) { if ($R.query) { $Reviewers.Add(@{ query = "$($R.query)"; queryType = "$($R.queryType)"; queryRoot = $R.queryRoot }) } }
            $HasGa = [bool]($Reviewers | Where-Object { $_.query -match $GlobalAdminRoleId })
            $Enabled = $Policy.isEnabled -eq $true -or "$($Policy.isEnabled)" -eq 'true'
            if ($Enabled -and $HasGa) {
                & $Add 'Consent requests' 'Success' 'Admin consent requests are already on, reviewed by Global Administrators.'
            } else {
                if (-not $HasGa) {
                    $Reviewers.Add(@{ query = "/beta/roleManagement/directory/roleAssignments?`$filter=roleDefinitionId eq '$GlobalAdminRoleId'"; queryType = 'MicrosoftGraph'; queryRoot = $null })
                }
                $Body = @{
                    isEnabled             = $true
                    notifyReviewers       = $true
                    remindersEnabled      = $true
                    requestDurationInDays = if ($Policy.requestDurationInDays) { [int]$Policy.requestDurationInDays } else { 30 }
                    reviewers             = @($Reviewers)
                } | ConvertTo-Json -Depth 5 -Compress
                $null = New-GraphPOSTRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $TenantFilter -type PUT -body $Body -contentType 'application/json'
                & $Add 'Consent requests' 'Success' 'Users can now ask for an app to be approved; Global Administrators review the requests.'
            }
        } catch { & $Add 'Consent requests' 'Error' "Couldn't turn on admin consent requests: $(& $ErrorText $_)" }
    }

    $Results
}
