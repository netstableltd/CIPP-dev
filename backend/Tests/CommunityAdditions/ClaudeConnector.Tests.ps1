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

    foreach ($Name in 'ConvertTo-CIPPODataFilterValue', 'Get-CIPPClaudeConnectorApps', 'Get-CIPPClaudeConnectorStatus', 'Set-CIPPClaudeConnector', 'Invoke-ExecClaudeConnector', 'Invoke-ListClaudeConnector',
        'Get-CIPPClaudeConnectorAccessConfig', 'Get-CIPPClaudeConnectorScopeSummary', 'Get-CIPPClaudeConnectorReadiness', 'Set-CIPPClaudeConnectorAccess', 'Build-CippClaudeConnectorCustomerTree', 'New-CippReportComponents') {
        . (& $Find "$Name.ps1")
    }

    $script:ClientAppId = '08ad6f98-a4f8-4635-bb8d-f1a3044760f0'
    $script:ServerAppId = '07c030f6-5743-41b7-ba00-0a6e85f37c17'
    $script:GaRole = '62e90394-69f5-4237-9190-012177145e10'
    $script:ReadScopes = 'User.Read User.ReadBasic.All offline_access Mail.Read Mail.ReadBasic Mail.Read.Shared MailboxFolder.Read MailboxItem.Read Calendars.Read Calendars.Read.Shared Files.Read Files.Read.All Sites.Read.All Chat.Read Chat.ReadBasic ChatMember.Read ChatMessage.Read Channel.ReadBasic.All ChannelMessage.Read.All OnlineMeetings.Read OnlineMeetingTranscript.Read.All OnlineMeetingAiInsight.Read OnlineMeetingArtifact.Read.All OnlineMeetingRecording.Read.All'
    $script:WriteScopes = 'Mail.Send Mail.ReadWrite MailboxSettings.ReadWrite Calendars.ReadWrite Files.ReadWrite.All ChatMessage.Send ChannelMessage.Send Chat.Create'
    $script:Scopes = { param($Grant) @("$($Grant.scope)" -split '\s+' | Where-Object { $_ }) }
    $script:TenantGrant = { $script:T.Grants | Where-Object { $_.clientId -eq 'sp-server' -and $_.consentType -eq 'AllPrincipals' } }
    $script:UserGrant = { param($U) $script:T.Grants | Where-Object { $_.clientId -eq 'sp-server' -and $_.consentType -eq 'Principal' -and $_.principalId -eq $U } }

    # A small fake tenant. Get/Post requests read and change $script:T; every write is logged in order.
    function New-FakeTenant {
        param([switch]$NoApps, [switch]$NoConsent, [switch]$GroupExists, [string[]]$Self = @('ManagePermissionGrantsForSelf.microsoft-user-default-legacy'), [switch]$ReadOnlyConsent)
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:FailAssign = $false
        $script:T = @{
            Sps     = @{}
            Grants  = [System.Collections.Generic.List[object]]::new()
            AllSps  = @(
                # What Barracuda's backup really looks like in a tenant: no 'Barracuda' in the name.
                [pscustomobject]@{ displayName = 'Cloud-to-Cloud-Backup'; appId = '09e6e8ef-2c94-4106-89dd-d0a7e500a886'; publisherName = 'Barracuda Networks, Inc.'; appOwnerOrganizationId = 'b893e0b8-2743-4fa7-81eb-0155a9060350'; accountEnabled = $true }
                [pscustomobject]@{ displayName = 'Barracuda M365 Link'; appId = '96641992-2be0-4e39-812f-59929b0e3690'; publisherName = 'Barracuda Networks, Inc.'; appOwnerOrganizationId = 'b893e0b8-2743-4fa7-81eb-0155a9060350'; accountEnabled = $true }
                [pscustomobject]@{ displayName = 'Microsoft Graph'; appOwnerOrganizationId = 'f8cdef31-a31e-4b4a-93e4-5f571e91255a'; accountEnabled = $true }
            )
            Assign  = @{}
            Users   = @{
                'jo@contoso.com'  = [pscustomobject]@{ id = 'u-jo'; userPrincipalName = 'jo@contoso.com'; displayName = 'Jo' }
                'sam@contoso.com' = [pscustomobject]@{ id = 'u-sam'; userPrincipalName = 'sam@contoso.com'; displayName = 'Sam' }
            }
            Groups  = @{}
            Members = @{}
            Auth    = [pscustomobject]@{ defaultUserRolePermissions = [pscustomobject]@{ permissionGrantPoliciesAssigned = @($Self + 'ManageOwnTeams') } }
            Request = [pscustomobject]@{ isEnabled = $false; requestDurationInDays = 14; reviewers = @([pscustomobject]@{ query = '/users/u-helpdesk'; queryType = 'MicrosoftGraph'; queryRoot = $null }) }
            Skus    = @([pscustomobject]@{ skuPartNumber = 'SPB'; capabilityStatus = 'Enabled'; servicePlans = @(
                        [pscustomobject]@{ servicePlanName = 'AAD_PREMIUM'; provisioningStatus = 'Success' }
                        [pscustomobject]@{ servicePlanName = 'MDE_SMB'; provisioningStatus = 'Success' }
                        [pscustomobject]@{ servicePlanName = 'ATP_ENTERPRISE'; provisioningStatus = 'Success' }) })
        }
        if (-not $NoApps) {
            $script:T.Sps[$script:ClientAppId] = [pscustomobject]@{ id = 'sp-client'; appId = $script:ClientAppId; appRoleAssignmentRequired = $false }
            $script:T.Sps[$script:ServerAppId] = [pscustomobject]@{ id = 'sp-server'; appId = $script:ServerAppId; appRoleAssignmentRequired = $false }
            $script:T.Assign['sp-client'] = [System.Collections.Generic.List[object]]::new()
            $script:T.Assign['sp-server'] = [System.Collections.Generic.List[object]]::new()
            if (-not $NoConsent) {
                $script:T.Grants.Add([pscustomobject]@{ id = 'gr-client'; clientId = 'sp-client'; consentType = 'AllPrincipals'; principalId = $null; resourceId = 'sp-server'; scope = 'access_as_user' })
                $Scope = if ($ReadOnlyConsent) { $script:ReadScopes } else { "$($script:ReadScopes) $($script:WriteScopes)" }
                $script:T.Grants.Add([pscustomobject]@{ id = 'gr-server'; clientId = 'sp-server'; consentType = 'AllPrincipals'; principalId = $null; resourceId = 'sp-graph'; scope = $Scope })
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
            "servicePrincipals\?\`$filter=appId eq '00000003-0000-0000-c000-000000000000'" { return [pscustomobject]@{ id = 'sp-graph' } }
            "servicePrincipals\?\`$filter=appId eq '([0-9a-f-]+)'" { $sp = $script:T.Sps[$Matches[1]]; if ($sp) { return $sp } else { return @() } }
            'servicePrincipals\?\$select=displayName' { return $script:T.AllSps }
            "oauth2PermissionGrants\?\`$filter=clientId eq '([^']+)'" { $C = $Matches[1]; return @($script:T.Grants | Where-Object { $_.clientId -eq $C }) }
            'groups/([^/]+)/transitiveMembers' { return @($script:T.Members[$Matches[1]] | ForEach-Object { [pscustomobject]@{ id = $_ } }) }
            'servicePrincipals/([^/]+)/appRoleAssignedTo' { return @($script:T.Assign[$Matches[1]]) }
            '/users/([^?]+)\?' { $K = $Matches[1]; $x = $script:T.Users[$K]; if (-not $x) { $x = $script:T.Users.Values | Where-Object id -EQ $K | Select-Object -First 1 }; if ($x) { return $x } else { throw 'Resource not found' } }
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
            'oauth2PermissionGrants$' { $script:T.Grants.Add([pscustomobject]@{ id = "gr-$($B.principalId)"; clientId = $B.clientId; consentType = $B.consentType; principalId = $B.principalId; resourceId = $B.resourceId; scope = $B.scope }); return }
            'oauth2PermissionGrants/(.+)$' {
                $Id = $Matches[1]; $G = $script:T.Grants | Where-Object id -EQ $Id
                if ($type -eq 'DELETE') { [void]$script:T.Grants.Remove($G) } else { $G.scope = $B.scope }
                return
            }
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

Describe 'Access levels and read areas' {
    It 'sets everyone to read only, keeping what Claude can read' {
        New-FakeTenant -GroupExists
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -TenantLevel 'read'
        $S = & $script:Scopes (& $script:TenantGrant)
        $S | Should -Not -Contain 'Mail.Send'
        $S | Should -Not -Contain 'Files.ReadWrite.All'
        $S | Should -Contain 'Mail.Read'
        $S | Should -Contain 'User.Read'
        ($R | Where-Object Step -EQ 'Access').Message | Should -Match 'Level 1'
        # Access only: nothing else touched.
        $script:Calls | Where-Object { $_ -match '/groups|appRoleAssignedTo|authorizationPolicy' } | Should -BeNullOrEmpty
    }

    It 'sets everyone to exactly one level' {
        New-FakeTenant -GroupExists
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -TenantLevel 'drafts'
        $S = & $script:Scopes (& $script:TenantGrant)
        @($S | Where-Object { $script:WriteScopes -split ' ' -contains $_ }) | Should -Be @('Mail.ReadWrite')
    }

    It 'turns read areas off and back on' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -ReadAreas 'mail', 'calendar', 'files'
        $S = & $script:Scopes (& $script:TenantGrant)
        $S | Should -Not -Contain 'Chat.Read'
        $S | Should -Not -Contain 'OnlineMeetingTranscript.Read.All'
        $S | Should -Contain 'Sites.Read.All'
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -ReadAreas 'mail', 'calendar', 'files', 'teams', 'meetings'
        (& $script:Scopes (& $script:TenantGrant)) | Should -Contain 'Chat.Read'
    }

    It 'does nothing when access is already as asked' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -TenantLevel 'read' -ReadAreas 'mail', 'calendar', 'files', 'teams', 'meetings'
        $script:Calls | Should -BeNullOrEmpty
        ($R | Where-Object Step -EQ 'Access').Message | Should -Match 'already has Level 1'
    }

    It 'gives one person extra access on top of everyone, then changes and removes it' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'assistant' })
        (& $script:Scopes (& $script:UserGrant 'u-jo') | Sort-Object) | Should -Be @('Calendars.ReadWrite', 'Mail.ReadWrite', 'Mail.Send', 'MailboxSettings.ReadWrite')
        (& $script:UserGrant 'u-jo').resourceId | Should -Be 'sp-graph'
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -PeopleLevels @(@{ User = 'u-jo'; Level = 'drafts' })
        (& $script:Scopes (& $script:UserGrant 'u-jo')) | Should -Be @('Mail.ReadWrite')
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'read' })
        & $script:UserGrant 'u-jo' | Should -BeNullOrEmpty
        (($R | Where-Object Step -EQ 'Access').Message -join ' ') | Should -Match 'removed their extra access'
    }

    It 'only adds what everyone does not already have' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -TenantLevel 'drafts' -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'drafts' })
        & $script:UserGrant 'u-jo' | Should -BeNullOrEmpty
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'assistant' })
        (& $script:Scopes (& $script:UserGrant 'u-jo') | Sort-Object) | Should -Be @('Calendars.ReadWrite', 'Mail.Send', 'MailboxSettings.ReadWrite')
    }

    It 'warns when the person is not one of the people who can use Claude' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com'
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -PeopleLevels @(@{ User = 'sam@contoso.com'; Level = 'drafts' })
        ($R | Where-Object Status -EQ 'Warning').Message | Should -Match "sam@contoso.com isn't one of the people"
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'drafts' })
        $R | Where-Object Status -EQ 'Warning' | Should -BeNullOrEmpty
    }

    It 'warns when a write permission lets Claude read something switched off' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -ReadAreas 'calendar' -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'drafts' })
        (($R | Where-Object Status -EQ 'Warning').Message -join ' ') | Should -Match 'also lets Claude read their email'
    }

    It 'applies access as part of Apply, after the assignments' {
        New-FakeTenant -GroupExists
        $R = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com' -TenantLevel 'read' -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'drafts' })
        (& $script:Scopes (& $script:TenantGrant)) | Should -Not -Contain 'Mail.Send'
        (& $script:Scopes (& $script:UserGrant 'u-jo')) | Should -Be @('Mail.ReadWrite')
        @($R | Where-Object Status -EQ 'Error').Count | Should -Be 0
    }

    It 'reports access in the status' {
        New-FakeTenant -GroupExists
        $S = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $S.Access.Level | Should -Be 'full'
        @($S.Access.ReadAreas).Count | Should -Be 5
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Access -TenantLevel 'read' -ReadAreas 'mail' -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'assistant' })
        $S = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $S.Access.Level | Should -Be 'read'
        @($S.Access.ReadAreas) | Should -Be @('mail')
        $S.Access.People[0].Upn | Should -Be 'jo@contoso.com'
        $S.Access.People[0].Level | Should -Be 'assistant'
    }
}

Describe 'Get-CIPPClaudeConnectorReadiness' {
    It 'finds Barracuda backup, Entra ID P1, Defender and Business Premium' {
        New-FakeTenant
        $R = Get-CIPPClaudeConnectorReadiness -TenantFilter 'contoso.com'
        $R.Backup.Barracuda | Should -BeTrue
        @($R.Backup.Products) | Should -Be @('Barracuda Cloud-to-Cloud Backup')
        $R.EntraP1 | Should -BeTrue
        $R.Defender.Products | Should -Contain 'Microsoft Defender for Business'
        $R.BusinessPremium | Should -BeTrue
    }
    It 'reports what is missing' {
        New-FakeTenant
        $script:T.AllSps = @(
            [pscustomobject]@{ displayName = 'Barracuda M365 Link'; publisherName = 'Barracuda Networks, Inc.'; appOwnerOrganizationId = 'b893e0b8-2743-4fa7-81eb-0155a9060350'; accountEnabled = $true }
            [pscustomobject]@{ displayName = 'BarracudaONE (prod)'; publisherName = 'Barracuda Networks, Inc.'; appOwnerOrganizationId = 'b893e0b8-2743-4fa7-81eb-0155a9060350'; accountEnabled = $true }
        )
        $script:T.Skus = @([pscustomobject]@{ skuPartNumber = 'O365_BUSINESS_PREMIUM'; capabilityStatus = 'Enabled'; servicePlans = @([pscustomobject]@{ servicePlanName = 'EXCHANGE_S_STANDARD'; provisioningStatus = 'Success' }) })
        $R = Get-CIPPClaudeConnectorReadiness -TenantFilter 'contoso.com'
        $R.Backup.Found | Should -BeFalse
        $R.EntraP1 | Should -BeFalse
        $R.Defender.Found | Should -BeFalse
        $R.Suite | Should -BeNullOrEmpty
    }
    It 'says unknown, not missing, when nothing comes back from the tenant' {
        New-FakeTenant
        $script:T.AllSps = @()
        $script:T.Skus = @()
        $R = Get-CIPPClaudeConnectorReadiness -TenantFilter 'contoso.com'
        $R.Backup | Should -BeNullOrEmpty
        $R.EntraP1 | Should -BeNullOrEmpty
        $R.Defender | Should -BeNullOrEmpty
    }
    It 'names another backup product' {
        New-FakeTenant
        $script:T.AllSps = @([pscustomobject]@{ displayName = 'SaaS Protection'; publisherName = 'Datto, Inc.'; appOwnerOrganizationId = 'd1'; accountEnabled = $true })
        $R = Get-CIPPClaudeConnectorReadiness -TenantFilter 'contoso.com'
        $R.Backup.Found | Should -BeTrue
        $R.Backup.Barracuda | Should -BeFalse
        @($R.Backup.Products) | Should -Be @('SaaS Protection')
    }
}

Describe 'Build-CippClaudeConnectorCustomerTree' {
    BeforeAll {
        $script:Text = { param($Tree) ($Tree.Blocks | ConvertTo-Json -Depth 10) }
    }
    It 'has the request, before-you-start checks, a page per level and the reply list' {
        $Ready = [pscustomobject]@{ Backup = [pscustomobject]@{ Found = $true; Barracuda = $true; Products = @('Barracuda Cloud-to-Cloud Backup') }; EntraP1 = $true; Defender = [pscustomobject]@{ Found = $true; Products = @('Microsoft Defender for Business') }; Suite = 'Microsoft 365 Business Premium'; BusinessPremium = $true }
        $Tree = Build-CippClaudeConnectorCustomerTree -TenantName 'Contoso Ltd' -Readiness $Ready -ContactName 'Jo' -PreparedBy 'Dave'
        $Titles = @($Tree.Blocks | Where-Object { $_.type -eq 'page' } | ForEach-Object { $_.title })
        $Titles | Should -Be @('Your request', 'Access levels', 'Levels 1 and 2', 'Levels 3 and 4', 'Next steps')
        ($Tree.Blocks | Where-Object { $_.type -eq 'blank' -and $_.title -like 'Level *' }).title | Should -Be @('Level 1: Read only', 'Level 2: Drafts and tidy-up', 'Level 3: Personal assistant', 'Level 4: Full access')
        $J = & $script:Text $Tree
        $J | Should -Match 'Dear Jo'
        $J | Should -Match 'You have Barracuda Cloud-to-Cloud Backup'
        $J | Should -Match 'You already have Business Premium'
        $J | Should -Not -Match 'quote for:'
        $Tree.Variables.covertenant | Should -Be 'Contoso Ltd'
    }
    It 'says what is missing and offers quotes' {
        $Ready = [pscustomobject]@{ Backup = [pscustomobject]@{ Found = $false; Barracuda = $false; Products = @() }; EntraP1 = $false; Defender = [pscustomobject]@{ Found = $false; Products = @() }; Suite = $null; BusinessPremium = $false }
        $J = & $script:Text (Build-CippClaudeConnectorCustomerTree -TenantName 'Contoso Ltd' -Readiness $Ready)
        $J | Should -Match "couldn't find a third-party backup"
        $J | Should -Match "don't currently have Entra ID P1"
        $J | Should -Match "don't currently have Microsoft Defender"
        $J | Should -Match 'quote for: a third-party backup'
        $J | Should -Match 'Microsoft 365 Business Premium\?'
    }
    It 'copes when nothing could be checked' {
        $J = & $script:Text (Build-CippClaudeConnectorCustomerTree -TenantName 'Contoso & Co' -Readiness ([pscustomobject]@{ Backup = $null; EntraP1 = $null; Defender = $null; Suite = $null }))
        $J | Should -Match 'To confirm'
        $J | Should -Match 'Contoso &amp; Co'
    }
}

Describe 'Invoke-ExecClaudeConnector access options' {
    BeforeEach { New-FakeTenant -GroupExists }
    It 'rejects an unknown level' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Access'; TenantLevel = 'admin' }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 400
    }
    It 'rejects an unknown read area and an empty list' {
        (Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Access'; ReadAreas = @('mail', 'x') }; Headers = @{}; Params = @{} }).StatusCode | Should -Be 400
        (Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Access'; ReadAreas = @() }; Headers = @{}; Params = @{} }).StatusCode | Should -Be 400
    }
    It 'needs something to change for Access' {
        (Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Access' }; Headers = @{}; Params = @{} }).StatusCode | Should -Be 400
    }
    It 'rejects a bad person' {
        (Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Access'; PeopleLevels = @(@{ User = '../x'; Level = 'read' }) }; Headers = @{}; Params = @{} }).StatusCode | Should -Be 400
    }
    It 'takes picker values and sets access' {
        $R = Invoke-ExecClaudeConnector -Request @{ Body = @{ tenantFilter = 'contoso.com'; Action = 'Access'; TenantLevel = @{ value = 'read' }; PeopleLevels = @(@{ User = @{ value = 'jo@contoso.com' }; Level = @{ value = 'drafts' } }) }; Headers = @{}; Params = @{} }
        $R.StatusCode | Should -Be 200
        $R.Body.Success | Should -BeTrue
        (& $script:Scopes (& $script:UserGrant 'u-jo')) | Should -Be @('Mail.ReadWrite')
    }
}

Describe 'Invoke-ListClaudeConnector options' {
    It 'returns the levels and read areas' {
        New-FakeTenant
        $R = Invoke-ListClaudeConnector -Request @{ Query = @{ tenantFilter = 'contoso.com' } }
        @($R.Body.Options.Levels).Count | Should -Be 4
        @($R.Body.Options.ReadAreas).Count | Should -Be 5
        $R.Body.Readiness.Backup.Barracuda | Should -BeTrue
    }
}

Describe 'Build-CippClaudeConnectorSummaryTree' {
    BeforeAll {
        . (Get-ChildItem -Path (Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules') -Recurse -Filter 'Build-CippClaudeConnectorSummaryTree.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)
        $script:Json = { param($Tree) $Tree.Blocks | ConvertTo-Json -Depth 10 }
    }
    It 'summarises a finished setup from the tenant status' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $null = Set-CIPPClaudeConnector -TenantFilter 'contoso.com' -Action Apply -Users 'jo@contoso.com', 'sam@contoso.com' -LockUserConsent -TenantLevel 'read' -PeopleLevels @(@{ User = 'jo@contoso.com'; Level = 'assistant' })
        $Status = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $Tree = Build-CippClaudeConnectorSummaryTree -TenantName 'Contoso Ltd' -Status $Status -ContactName 'Jo' -GeneratedOn '29 October 2026'
        @($Tree.Blocks | Where-Object { $_.type -eq 'page' } | ForEach-Object { $_.title }) | Should -Be @("What we've set up", 'Keeping it safe')
        $People = ($Tree.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.title -eq 'Who can use Claude' }).rows
        ($People | Where-Object { $_.person -like 'Jo*' }).level | Should -Be 'Level 3: Personal assistant'
        ($People | Where-Object { $_.person -like 'Sam*' }).level | Should -Be 'Level 1: Read only'
        $J = & $script:Json $Tree
        $J | Should -Match 'Dear Jo'
        $J | Should -Not -Match 'Still to finish'
        $Guards = ($Tree.Blocks | Where-Object { $_.type -eq 'richtable' -and $_.title -eq 'Safeguards' }).rows
        ($Guards | Where-Object { $_.what -eq 'Named people only' }).status | Should -Be 'In place'
        ($Guards | Where-Object { $_.what -eq 'No unapproved apps' }).status | Should -Be 'In place'
        ($Guards | Where-Object { $_.what -eq 'Third-party backup' }).status | Should -Be 'In place'
        $Tree.Variables.coverpanel | Should -Be 'true'
    }
    It 'says what is not finished' {
        New-FakeTenant -NoConsent
        $Status = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $J = & $script:Json (Build-CippClaudeConnectorSummaryTree -TenantName 'Contoso Ltd' -Status $Status)
        $J | Should -Match 'Still to finish'
        $J | Should -Match "admin consent for Claude hasn't been given"
        $J | Should -Match 'Nobody can use Claude yet'
    }
    It 'warns when consent left everyone with full access' {
        New-FakeTenant -GroupExists
        $Status = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $J = & $script:Json (Build-CippClaudeConnectorSummaryTree -TenantName 'Contoso Ltd' -Status $Status)
        $J | Should -Match 'Everyone currently has full access'
        $J | Should -Match 'not yet limited to named people'
    }
}

Describe 'Connection guide' {
    BeforeAll {
        $Root = Join-Path (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))) 'Modules'
        foreach ($Name in 'ConvertFrom-CIPPDocxGuide', 'Get-CIPPClaudeConnectorGuide', 'Invoke-ExecClaudeConnectorGuide', 'Build-CippClaudeConnectorSummaryTree') {
            . (Get-ChildItem -Path $Root -Recurse -Filter "$Name.ps1" -File | Select-Object -First 1 -ExpandProperty FullName)
        }
        Add-Type -AssemblyName System.IO.Compression
        function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
        function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
        function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
        function Remove-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }

        # A made-up guide built the way Word stores one.
        $script:NewDocx = {
            param([string]$BodyXml)
            $W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
            $Doc = "<?xml version=`"1.0`"?><w:document xmlns:w=`"$W`" xmlns:r=`"http://schemas.openxmlformats.org/officeDocument/2006/relationships`" xmlns:a=`"http://schemas.openxmlformats.org/drawingml/2006/main`" xmlns:wp=`"http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing`"><w:body>$BodyXml<w:sectPr/></w:body></w:document>"
            $Rels = '<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId9" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/image1.png"/></Relationships>'
            $Png = [Convert]::FromBase64String('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==')
            $Ms = [System.IO.MemoryStream]::new()
            $Zip = [System.IO.Compression.ZipArchive]::new($Ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
            foreach ($E in @(@('word/document.xml', [Text.Encoding]::UTF8.GetBytes($Doc)), @('word/_rels/document.xml.rels', [Text.Encoding]::UTF8.GetBytes($Rels)), @('word/media/image1.png', $Png))) {
                $S = $Zip.CreateEntry($E[0]).Open(); $S.Write($E[1], 0, $E[1].Length); $S.Dispose()
            }
            $Zip.Dispose()
            , $Ms.ToArray()
        }
        $P = {
            param($Text, [switch]$Bold, [string]$Style, [switch]$List)
            $Ppr = ''
            if ($Style -or $List) {
                $Ppr = '<w:pPr>'
                if ($Style) { $Ppr += '<w:pStyle w:val="' + $Style + '"/>' }
                if ($List) { $Ppr += '<w:numPr><w:numId w:val="1"/></w:numPr>' }
                $Ppr += '</w:pPr>'
            }
            $Rpr = if ($Bold) { '<w:rPr><w:b/></w:rPr>' } else { '' }
            '<w:p>' + $Ppr + '<w:r>' + $Rpr + '<w:t xml:space="preserve">' + $Text + '</w:t></w:r></w:p>'
        }
        $Img = '<w:p><w:r><w:drawing><wp:inline><wp:extent cx="1270000" cy="635000"/><a:graphic><a:graphicData><a:blip r:embed="rId9"/></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>'
        $script:Body = @(
            (& $P 'CONTOSO HOW-TO' -Bold)
            (& $P 'Connecting Claude')
            (& $P 'Three short steps.')
            '<w:p><w:r><w:t xml:space="preserve">Intro with </w:t></w:r><w:r><w:rPr><w:b/></w:rPr><w:t>bold</w:t></w:r><w:r><w:t xml:space="preserve"> text.</w:t></w:r></w:p>'
            (& $P 'Adding it' -Style 'Heading2')
            (& $P "$([char]0xA0)1$([char]0xA0)$([char]0xA0)Open Settings" -Bold)
            $Img
            (& $P 'First example' -List)
            (& $P 'Second example' -List)
            "<w:tbl><w:tr><w:tc>$(& $P 'Important: backups' -Bold)$(& $P 'Keep a backup.')</w:tc></w:tr></w:tbl>"
            "<w:tbl><w:tr><w:tc>$Img</w:tc><w:tc>$Img</w:tc></w:tr></w:tbl>"
        ) -join ''
    }

    It 'turns a Word guide into report blocks' {
        $G = ConvertFrom-CIPPDocxGuide -Bytes (& $script:NewDocx $script:Body)
        $G.Title | Should -Be 'Connecting Claude'
        $G.Subtitle | Should -Be 'Three short steps.'
        $G.Images | Should -Be 3
        $Types = @($G.Blocks | ForEach-Object { $_.type })
        $Types | Should -Be @('blank', 'blank', 'blank', 'image', 'richbullets', 'infobox', 'imagerow')
        $G.Blocks[0].content | Should -Be '<p>Intro with <b>bold</b> text.</p>'
        $G.Blocks[1].title | Should -Be 'Adding it'
        $G.Blocks[2].title | Should -Be '1. Open Settings'
        $G.Blocks[3].image | Should -Match '^data:image/png;base64,'
        $G.Blocks[3].width | Should -Be 100
        @($G.Blocks[4].items.text) | Should -Be @('First example', 'Second example')
        $G.Blocks[5].title | Should -Be 'Important: backups'
        $G.Blocks[5].tone | Should -Be 'warn'
        $G.Blocks[5].content | Should -Be 'Keep a backup.'
        @($G.Blocks[6].images).Count | Should -Be 2
    }

    It 'refuses a file that is not a Word document' {
        { ConvertFrom-CIPPDocxGuide -Bytes ([Text.Encoding]::UTF8.GetBytes('not a zip')) } | Should -Throw '*not a Word document*'
    }

    It 'is added to the end of the summary, and the summary points to it' {
        New-FakeTenant -GroupExists -ReadOnlyConsent
        $Status = Get-CIPPClaudeConnectorStatus -TenantFilter 'contoso.com'
        $G = ConvertFrom-CIPPDocxGuide -Bytes (& $script:NewDocx $script:Body)
        $Tree = Build-CippClaudeConnectorSummaryTree -TenantName 'Contoso Ltd' -Status $Status -Guide $G
        $Pages = @($Tree.Blocks | Where-Object { $_.type -eq 'page' })
        $Pages[-1].title | Should -Be 'Connecting Claude'
        $Tree.Blocks[-1].type | Should -Be 'imagerow'
        ($Tree.Blocks | ConvertTo-Json -Depth 10) | Should -Match 'guide at the end of this document'
    }

    Context 'upload and remove' {
        BeforeEach {
            $script:Saved = $null
            $script:Removed = $false
            Mock Get-CIPPTable { @{ TableName = 'CommunityProcesses' } }
            Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
            Mock Get-CIPPAzDataTableEntity { if ($script:Saved) { [pscustomobject]$script:Saved } }
            Mock Remove-CIPPAzDataTableEntity { $script:Removed = $true; $script:Saved = $null }
        }
        It 'saves a readable guide and reports it' {
            $Data = [Convert]::ToBase64String((& $script:NewDocx $script:Body))
            $R = Invoke-ExecClaudeConnectorGuide -Request @{ Body = @{ Action = 'Upload'; FileName = 'C:\fakepath\How-to.docx'; Data = "data:application/octet-stream;base64,$Data" }; Headers = @{}; Params = @{} }
            $R.StatusCode | Should -Be 200
            $script:Saved.FileName | Should -Be 'How-to.docx'
            $script:Saved.Title | Should -Be 'Connecting Claude'
            $R.Body.Results | Should -Match '3 pictures'
            (Get-CIPPClaudeConnectorGuide).Title | Should -Be 'Connecting Claude'
            (Get-CIPPClaudeConnectorGuide -IncludeFile).Bytes.Length | Should -BeGreaterThan 0
        }
        It 'refuses other files' {
            (Invoke-ExecClaudeConnectorGuide -Request @{ Body = @{ Action = 'Upload'; FileName = 'guide.pdf'; Data = 'AAAA' }; Headers = @{}; Params = @{} }).StatusCode | Should -Be 400
            (Invoke-ExecClaudeConnectorGuide -Request @{ Body = @{ Action = 'Upload'; FileName = 'guide.docx'; Data = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('nope')) }; Headers = @{}; Params = @{} }).StatusCode | Should -Be 400
            $script:Saved | Should -BeNullOrEmpty
        }
        It 'removes the guide' {
            $script:Saved = @{ PartitionKey = 'ClaudeM365'; RowKey = 'Guide'; Docx = 'AA==' }
            $R = Invoke-ExecClaudeConnectorGuide -Request @{ Body = @{ Action = 'Remove' }; Headers = @{}; Params = @{} }
            $R.StatusCode | Should -Be 200
            $script:Removed | Should -BeTrue
            Get-CIPPClaudeConnectorGuide | Should -BeNullOrEmpty
        }
    }
}
