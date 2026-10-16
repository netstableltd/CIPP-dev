# Pester tests for the Claude for Microsoft 365 standard process (Community Additions > Standard Processes).
#
# Pins: AddApps creates only the missing service principals; Apply refuses to change anything until both
# apps have admin consent; group mode creates/reuses the group, adds only new members, assigns the group to
# both apps BEFORE turning on "Assignment required", and removes direct assignments the group covers while
# leaving (and reporting) other ones; direct mode assigns users and makes no group; a failed assignment
# leaves "Assignment required" off; LockUserConsent removes self-consent policies (but leaves CIPP's own
# consent policy alone) and adds Global Administrators as consent request reviewers, keeping existing ones;
# the status reader reports each part; the HTTP endpoint validates its input.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function Get-Tenants { param($TenantFilter) [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111'; defaultDomainName = 'contoso.com' } }
    function Start-Sleep { param($Seconds) }

    foreach ($Name in 'ConvertTo-CIPPODataFilterValue', 'Get-CIPPClaudeConnectorApps', 'Get-CIPPClaudeConnectorStatus', 'Set-CIPPClaudeConnector', 'Invoke-ExecClaudeConnector', 'Invoke-ListClaudeConnector') {
        . (& $Find "$Name.ps1")
    }

    $script:ClientAppId = '08ad6f98-a4f8-4635-bb8d-f1a3044760f0'
    $script:ServerAppId = '07c030f6-5743-41b7-ba00-0a6e85f37c17'
    $script:GaRole = '62e90394-69f5-4237-9190-012177145e10'

    # A small fake tenant. Get/Post requests read and change $script:T; every write is logged in order.
    function New-FakeTenant {
        param([switch]$NoApps, [switch]$NoConsent, [switch]$GroupExists, [string[]]$Self = @('ManagePermissionGrantsForSelf.microsoft-user-default-legacy'))
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:FailAssign = $false
        $script:T = @{
            Sps     = @{}
            Grants  = @{}
            Assign  = @{}
            Users   = @{
                'jo@contoso.com'  = [pscustomobject]@{ id = 'u-jo'; userPrincipalName = 'jo@contoso.com'; displayName = 'Jo' }
                'sam@contoso.com' = [pscustomobject]@{ id = 'u-sam'; userPrincipalName = 'sam@contoso.com'; displayName = 'Sam' }
            }
            Groups  = @{}
            Members = @{}
            Auth    = [pscustomobject]@{ defaultUserRolePermissions = [pscustomobject]@{ permissionGrantPoliciesAssigned = @($Self + 'ManageOwnTeams') } }
            Request = [pscustomobject]@{ isEnabled = $false; requestDurationInDays = 14; reviewers = @([pscustomobject]@{ query = '/users/u-helpdesk'; queryType = 'MicrosoftGraph'; queryRoot = $null }) }
            Skus    = @([pscustomobject]@{ capabilityStatus = 'Enabled'; servicePlans = @([pscustomobject]@{ servicePlanName = 'AAD_PREMIUM'; provisioningStatus = 'Success' }) })
        }
        if (-not $NoApps) {
            $script:T.Sps[$script:ClientAppId] = [pscustomobject]@{ id = 'sp-client'; appId = $script:ClientAppId; appRoleAssignmentRequired = $false }
            $script:T.Sps[$script:ServerAppId] = [pscustomobject]@{ id = 'sp-server'; appId = $script:ServerAppId; appRoleAssignmentRequired = $false }
            $script:T.Assign['sp-client'] = [System.Collections.Generic.List[object]]::new()
            $script:T.Assign['sp-server'] = [System.Collections.Generic.List[object]]::new()
            if (-not $NoConsent) {
                $script:T.Grants['sp-client'] = @([pscustomobject]@{ consentType = 'AllPrincipals' })
                $script:T.Grants['sp-server'] = @([pscustomobject]@{ consentType = 'AllPrincipals' })
            }
        }
        if ($GroupExists) {
            $script:T.Groups['SG-Claude-Users'] = [pscustomobject]@{ id = 'g-claude'; displayName = 'SG-Claude-Users' }
            $script:T.Members['g-claude'] = [System.Collections.Generic.List[string]]::new()
            $script:T.Members['g-claude'].Add('u-jo')
        }
    }

    function New-GraphGetRequest {
        param($uri, $tenantid, $noPagination, $AsApp)
        $u = [System.Uri]::UnescapeDataString($uri)
        switch -Regex ($u) {
            "servicePrincipals\?\`$filter=appId eq '([0-9a-f-]+)'" { $sp = $script:T.Sps[$Matches[1]]; if ($sp) { return $sp } else { return @() } }
            "oauth2PermissionGrants\?\`$filter=clientId eq '([^']+)'" { return @($script:T.Grants[$Matches[1]]) }
            'servicePrincipals/([^/]+)/appRoleAssignedTo' { return @($script:T.Assign[$Matches[1]]) }
            '/users/([^?]+)\?' { $x = $script:T.Users[$Matches[1]]; if ($x) { return $x } else { throw 'Resource not found' } }
            "groups\?\`$filter=displayName eq '([^']+)'" { $g = $script:T.Groups[$Matches[1]]; if ($g) { return $g } else { return @() } }
            'groups/([^/]+)/members' { $Id = $Matches[1]; return @($script:T.Members[$Id] | ForEach-Object { $M = $_; $U = $script:T.Users.Values | Where-Object id -EQ $M; [pscustomobject]@{ id = $M; displayName = $U.displayName; userPrincipalName = $U.userPrincipalName } }) }
            'subscribedSkus' { return $script:T.Skus }
            'policies/authorizationPolicy' { return $script:T.Auth }
            'adminConsentRequestPolicy' { return $script:T.Request }
            default { throw "Unexpected GET $u" }
        }
    }

    function New-GraphPOSTRequest {
        param($uri, $tenantid, $body, $type = 'POST', $contentType, $AsApp)
        $script:Calls.Add("$type $($uri -replace 'https://graph.microsoft.com/(v1.0|beta)', '') $body")
        $B = if ($body) { $body | ConvertFrom-Json } else { $null }
        switch -Regex ($uri) {
            'servicePrincipals$' { $id = "sp-new-$($B.appId.Substring(0,4))"; $script:T.Sps[$B.appId] = [pscustomobject]@{ id = $id; appId = $B.appId; appRoleAssignmentRequired = $false }; $script:T.Assign[$id] = [System.Collections.Generic.List[object]]::new(); return }
            'groups$' { $g = [pscustomobject]@{ id = 'g-new'; displayName = $B.displayName }; $script:T.Groups[$B.displayName] = $g; $script:T.Members['g-new'] = [System.Collections.Generic.List[string]]::new(); return $g }
            'groups/([^/]+)/members/\$ref' { $script:T.Members[$Matches[1]].Add(($B.'@odata.id' -split '/')[-1]); return }
            'servicePrincipals/([^/]+)/appRoleAssignedTo$' {
                if ($script:FailAssign) { throw 'Request_BadRequest' }
                $script:T.Assign[$Matches[1]].Add([pscustomobject]@{ id = "a-$($B.principalId)"; principalId = $B.principalId; principalType = 'Group'; principalDisplayName = 'x' }); return
            }
            'servicePrincipals/([^/]+)/appRoleAssignedTo/(.+)$' { $Sp = $Matches[1]; $Id = $Matches[2]; $L = $script:T.Assign[$Sp]; $Item = $L | Where-Object id -EQ $Id; [void]$L.Remove($Item); return }
            'servicePrincipals/([^/]+)$' { ($script:T.Sps.Values | Where-Object id -EQ $Matches[1]).appRoleAssignmentRequired = $true; return }
            'authorizationPolicy' { $script:T.Auth.defaultUserRolePermissions.permissionGrantPoliciesAssigned = @($B.defaultUserRolePermissions.permissionGrantPoliciesAssigned); return }
            'adminConsentRequestPolicy' { $script:T.Request = $B; return }
            default { throw "Unexpected $type $uri" }
        }
    }
}

Describe 'Set-CIPPClaudeConnector -Action AddApps' {
    It 'adds both service principals when missing' {
        New-FakeTenant -NoApps
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action AddApps
        @($script:Calls | Where-Object { $_ -like 'POST /servicePrincipals *' }).Count | Should -Be 2
        @($R | Where-Object Status -EQ 'Success').Count | Should -Be 2
    }
    It 'does nothing when both are already there' {
        New-FakeTenant
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action AddApps
        $script:Calls.Count | Should -Be 0
        ($R.Message -join ' ') | Should -Match 'already in the tenant'
    }
}

Describe 'Set-CIPPClaudeConnector -Action Apply' {
    It 'changes nothing until both apps have admin consent' {
        New-FakeTenant -NoConsent
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com'
        $script:Calls.Count | Should -Be 0
        $R[-1].Status | Should -Be 'Error'
        $R[-1].Message | Should -Match 'admin consent'
    }

    It 'stops when none of the users exist' {
        New-FakeTenant
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'nobody@contoso.com'
        $script:Calls.Count | Should -Be 0
        $R[-1].Status | Should -Be 'Error'
    }

    It 'creates the group, adds users, assigns it to both apps, then requires assignment' {
        New-FakeTenant
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com', 'sam@contoso.com', 'ghost@contoso.com'
        $script:T.Groups['SG-Claude-Users'].id | Should -Be 'g-new'
        @($script:T.Members['g-new']) | Should -Be @('u-jo', 'u-sam')
        $script:T.Assign['sp-client'].principalId | Should -Contain 'g-new'
        $script:T.Assign['sp-server'].principalId | Should -Contain 'g-new'
        $script:T.Sps[$script:ClientAppId].appRoleAssignmentRequired | Should -BeTrue
        $script:T.Sps[$script:ServerAppId].appRoleAssignmentRequired | Should -BeTrue
        # Assignment before "Assignment required", per app.
        $AssignIdx = $script:Calls.FindIndex([Predicate[string]] { param($c) $c -like 'POST /servicePrincipals/sp-client/appRoleAssignedTo *' })
        $RequireIdx = $script:Calls.FindIndex([Predicate[string]] { param($c) $c -like 'PATCH /servicePrincipals/sp-client *' })
        $AssignIdx | Should -BeLessThan $RequireIdx
        ($R | Where-Object Status -EQ 'Warning').Message | Should -Match 'ghost@contoso.com'
        @($R | Where-Object Status -EQ 'Error').Count | Should -Be 0
        # Group is a security group, not mail-enabled.
        $GroupCall = $script:Calls | Where-Object { $_ -like 'POST /groups {*' }
        ($GroupCall -replace '^POST /groups ', '' | ConvertFrom-Json).securityEnabled | Should -BeTrue
    }

    It 'reuses an existing group and only adds new members; is a no-op when run again' {
        New-FakeTenant -GroupExists
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com', 'sam@contoso.com'
        @($script:Calls | Where-Object { $_ -like 'POST /groups {*' }).Count | Should -Be 0
        @($script:Calls | Where-Object { $_ -like 'POST /groups/g-claude/members*' }).Count | Should -Be 1
        $script:Calls.Clear()
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com', 'sam@contoso.com'
        $script:Calls.Count | Should -Be 0
    }

    It 'removes direct assignments the group covers and reports other ones' {
        New-FakeTenant -GroupExists
        $script:T.Assign['sp-client'].Add([pscustomobject]@{ id = 'd-jo'; principalId = 'u-jo'; principalType = 'User'; principalDisplayName = 'Jo' })
        $script:T.Assign['sp-client'].Add([pscustomobject]@{ id = 'd-admin'; principalId = 'u-admin'; principalType = 'User'; principalDisplayName = 'Admin' })
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com'
        $script:T.Assign['sp-client'].id | Should -Not -Contain 'd-jo'
        $script:T.Assign['sp-client'].id | Should -Contain 'd-admin'
        ($R | Where-Object Status -EQ 'Warning').Message | Should -Match 'Admin is assigned directly'
    }

    It 'removes other direct assignments too with -RemoveOtherDirect' {
        New-FakeTenant -GroupExists
        $script:T.Assign['sp-client'].Add([pscustomobject]@{ id = 'd-admin'; principalId = 'u-admin'; principalType = 'User'; principalDisplayName = 'Admin' })
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com' -RemoveOtherDirect
        $script:T.Assign['sp-client'].id | Should -Not -Contain 'd-admin'
    }

    It 'assigns users directly and makes no group with -AssignUsersDirectly' {
        New-FakeTenant
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com', 'sam@contoso.com' -AssignUsersDirectly
        $script:T.Groups.Count | Should -Be 0
        @($script:T.Assign['sp-server'].principalId) | Should -Be @('u-jo', 'u-sam')
        $script:T.Sps[$script:ServerAppId].appRoleAssignmentRequired | Should -BeTrue
    }

    It 'leaves assignment required off when an assignment fails' {
        New-FakeTenant -GroupExists
        $script:FailAssign = $true
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com'
        $script:T.Sps[$script:ClientAppId].appRoleAssignmentRequired | Should -BeFalse
        @($R | Where-Object Status -EQ 'Error').Count | Should -BeGreaterThan 0
    }

    It 'does not touch consent settings without -LockUserConsent' {
        New-FakeTenant -GroupExists
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com'
        $script:Calls | Where-Object { $_ -match 'authorizationPolicy|adminConsentRequestPolicy' } | Should -BeNullOrEmpty
    }

    It 'turns off self-consent and adds Global Administrators as reviewers, keeping existing reviewers' {
        New-FakeTenant -GroupExists
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com' -LockUserConsent
        @($script:T.Auth.defaultUserRolePermissions.permissionGrantPoliciesAssigned) | Should -Be @('ManageOwnTeams')
        $script:T.Request.isEnabled | Should -BeTrue
        $script:T.Request.requestDurationInDays | Should -Be 14
        @($script:T.Request.reviewers.query) | Should -Contain '/users/u-helpdesk'
        ($script:T.Request.reviewers.query -join ' ') | Should -Match $script:GaRole
    }

    It "leaves CIPP's own consent policy alone" {
        New-FakeTenant -GroupExists -Self 'ManagePermissionGrantsForSelf.cipp-consent-policy'
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com' -LockUserConsent
        $script:Calls | Where-Object { $_ -match 'PATCH /policies/authorizationPolicy' } | Should -BeNullOrEmpty
        ($R | Where-Object Step -EQ 'User consent').Message | Should -Match 'standard'
    }
}

Describe 'Get-CIPPClaudeConnectorStatus' {
    It 'reports a fresh tenant' {
        New-FakeTenant -NoApps
        $S = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $S.AppsAdded | Should -BeFalse
        $S.Consented | Should -BeFalse
        $S.Apps[0].ConsentUrl | Should -Be "https://login.microsoftonline.com/11111111-1111-1111-1111-111111111111/adminconsent?client_id=$($script:ClientAppId)"
        $S.EntraP1 | Should -BeTrue
        $S.UserConsent.Allowed | Should -BeTrue
        $S.AdminConsentRequests.Enabled | Should -BeFalse
    }
    It 'reports a finished tenant' {
        New-FakeTenant -GroupExists
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com' -LockUserConsent
        $S = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $S.Consented | Should -BeTrue
        $S.Restricted | Should -BeTrue
        $S.AssignedByGroup | Should -BeTrue
        $S.Group.Members.Upn | Should -Contain 'jo@contoso.com'
        $S.UserConsent.Allowed | Should -BeFalse
        $S.AdminConsentRequests.GlobalAdminsReview | Should -BeTrue
    }
}

Describe 'Invoke-ExecClaudeConnector' {
    BeforeEach { New-FakeTenant }
    It 'rejects All Tenants' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'AllTenants'; Action = 'AddApps' }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 400
    }
    It 'rejects an unknown action' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Delete' }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 400
    }
    It 'needs users to apply' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Apply'; Users = @() }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 400
    }
    It 'rejects a bad group name' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Apply'; Users = @('jo@contoso.com'); GroupName = "x' or 1 eq 1" }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 400
    }
    It 'rejects values that are not user ids or sign-in names' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Apply'; Users = @('../groups/x') }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 400
    }
    It 'takes users from the user picker and returns the steps' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Apply'; Users = @(@{ value = 'jo@contoso.com'; label = 'Jo' }); LockUserConsent = 'true' }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 200
        $R.Body.Success | Should -BeTrue
        ($R.Body.Results.Step) | Should -Contain 'Consent requests'
    }
}

Describe 'Invoke-ListClaudeConnector' {
    It 'returns the status for a tenant' {
        New-FakeTenant
        $R = Invoke-ListClaudeConnector -Request @{ Query = @{ tenantFilter = 'contoso.com' } }
        $R.StatusCode | Should -Be 200
        $R.Body.AppsAdded | Should -BeTrue
    }
    It 'rejects All Tenants' {
        $R = Invoke-ListClaudeConnector -Request @{ Query = @{ tenantFilter = 'AllTenants' } }
        $R.StatusCode | Should -Be 400
    }
}
