function Get-CIPPClaudeConnectorStatus {
    <#
    .SYNOPSIS
        Reads how far a tenant is through setting up the Claude connector for Microsoft 365.

    .DESCRIPTION
        Read-only. For each of the two Claude apps (Get-CIPPClaudeConnectorApps): whether its service principal
        exists, whether it has tenant-wide admin consent, whether user assignment is required and who is
        assigned. Also the access group and its members, whether the tenant has Entra ID P1 (needed to assign
        a group to an app), whether users can consent to apps themselves, and whether admin consent requests
        are on with Global Administrators as reviewers.

        Access: the 'M365 MCP Server for Claude' app's tenant-wide Graph scopes, described as the read areas
        that are on and the access level they match (Config/ClaudeConnectorAccess.json), plus any people with
        their own extra access. Readiness: Get-CIPPClaudeConnectorReadiness (backup, P1, Defender, suite).

        Each part is read separately; a part that can't be read carries an Error and the rest still return.

    .PARAMETER TenantFilter
        Default domain or tenant id.

    .PARAMETER GroupName
        Access group to look for. Default SG-Claude-Users.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [string]$GroupName = 'SG-Claude-Users'
    )

    $GlobalAdminRoleId = '62e90394-69f5-4237-9190-012177145e10'
    $Tenant = Get-Tenants -TenantFilter $TenantFilter | Select-Object -First 1
    $TenantId = if ($Tenant.customerId) { "$($Tenant.customerId)" } else { $TenantFilter }
    $ErrorText = { param($E) try { (Get-CippException -Exception $E).NormalizedError } catch { "$($E.Exception.Message)" } }

    # --- Apps ---------------------------------------------------------------------------------------------
    $Apps = foreach ($App in Get-CIPPClaudeConnectorApps) {
        $Entry = [ordered]@{
            Key                = $App.Key
            Name               = $App.Name
            AppId              = $App.AppId
            Exists             = $false
            ServicePrincipalId = $null
            Consented          = $false
            ConsentUrl         = "https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$($App.AppId)"
            AssignmentRequired = $false
            Assigned           = @()
            Error              = $null
        }
        try {
            $Sp = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($App.AppId)'&`$select=id,appId,displayName,appRoleAssignmentRequired" -tenantid $TenantFilter) | Select-Object -First 1
            if ($Sp.id) {
                $Entry.Exists = $true
                $Entry.ServicePrincipalId = $Sp.id
                $Entry.AssignmentRequired = [bool]$Sp.appRoleAssignmentRequired
                $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($Sp.id)'" -tenantid $TenantFilter)
                $Entry.Consented = [bool]($Grants | Where-Object { $_.consentType -eq 'AllPrincipals' })
                $Entry.Assigned = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals/$($Sp.id)/appRoleAssignedTo?`$top=999" -tenantid $TenantFilter | ForEach-Object {
                        [pscustomobject]@{ Id = $_.id; PrincipalId = $_.principalId; Name = $_.principalDisplayName; Type = $_.principalType }
                    })
            }
        } catch { $Entry.Error = & $ErrorText $_ }
        [pscustomobject]$Entry
    }

    # --- Group ---------------------------------------------------------------------------------------------
    $Group = [ordered]@{ Name = $GroupName; Exists = $false; Id = $null; Members = @(); Error = $null }
    if ($GroupName) {
        try {
            $SafeName = ConvertTo-CIPPODataFilterValue -Value $GroupName -Type String
            $Filter = [System.Uri]::EscapeDataString("displayName eq '$SafeName'")
            $Found = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups?`$filter=$Filter&`$select=id,displayName,securityEnabled" -tenantid $TenantFilter) | Select-Object -First 1
            if ($Found.id) {
                $Group.Exists = $true
                $Group.Id = $Found.id
                $Group.Members = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/groups/$($Found.id)/members?`$select=id,displayName,userPrincipalName&`$top=999" -tenantid $TenantFilter | ForEach-Object {
                        [pscustomobject]@{ Id = $_.id; Name = $_.displayName; Upn = $_.userPrincipalName }
                    })
            }
        } catch { $Group.Error = & $ErrorText $_ }
    }

    # --- What the tenant already has (backup, P1, Defender, Business Premium) ------------------------------
    $Readiness = Get-CIPPClaudeConnectorReadiness -TenantFilter $TenantFilter
    $EntraP1 = $Readiness.EntraP1

    # --- What Claude can read and change -------------------------------------------------------------------
    # Admin consent gives the 'M365 MCP Server for Claude' app one tenant-wide (AllPrincipals) grant to
    # Microsoft Graph; extra write access for one person is a separate per-user (Principal) grant.
    $Access = [ordered]@{ TenantScopes = @(); ReadAreas = @(); Level = $null; WriteScopes = @(); People = @(); Error = $null }
    $Server = $Apps | Where-Object { $_.Key -eq 'Server' } | Select-Object -First 1
    if ($Server.ServicePrincipalId) {
        try {
            $GraphSp = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '00000003-0000-0000-c000-000000000000'&`$select=id" -tenantid $TenantFilter) | Select-Object -First 1
            $Grants = @(New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$($Server.ServicePrincipalId)'" -tenantid $TenantFilter | Where-Object { $_.resourceId -eq $GraphSp.id })
            $Tenant = $Grants | Where-Object { $_.consentType -eq 'AllPrincipals' } | Select-Object -First 1
            if ($Tenant) {
                $Access.TenantScopes = @("$($Tenant.scope)" -split '\s+' | Where-Object { $_ })
                $Summary = Get-CIPPClaudeConnectorScopeSummary -Scopes $Access.TenantScopes
                $Access.ReadAreas = @($Summary.ReadAreas)
                $Access.Level = $Summary.Level
                $Access.WriteScopes = @($Summary.WriteScopes)
            }
            $Access.People = @($Grants | Where-Object { $_.consentType -eq 'Principal' } | ForEach-Object {
                    $G = $_
                    $Scopes = @("$($G.scope)" -split '\s+' | Where-Object { $_ })
                    $Summary = Get-CIPPClaudeConnectorScopeSummary -Scopes $Scopes
                    $U = try { New-GraphGetRequest -uri "https://graph.microsoft.com/v1.0/users/$($G.principalId)?`$select=id,displayName,userPrincipalName" -tenantid $TenantFilter -noPagination $true | Select-Object -First 1 } catch { $null }
                    [pscustomobject]@{
                        UserId      = $G.principalId
                        Name        = if ($U.displayName) { $U.displayName } else { $G.principalId }
                        Upn         = $U.userPrincipalName
                        Scopes      = $Scopes
                        WriteScopes = @($Summary.WriteScopes)
                        Level       = $Summary.Level
                    }
                })
        } catch { $Access.Error = & $ErrorText $_ }
    }

    # --- User consent --------------------------------------------------------------------------------------
    $UserConsent = [ordered]@{ Allowed = $null; Policies = @(); ManagedByCipp = $false; Error = $null }
    try {
        $Auth = New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/policies/authorizationPolicy' -tenantid $TenantFilter | Select-Object -First 1
        $SelfPolicies = @($Auth.defaultUserRolePermissions.permissionGrantPoliciesAssigned | Where-Object { "$_" -like 'ManagePermissionGrantsForSelf.*' })
        $UserConsent.Policies = @($SelfPolicies)
        # CIPP's "Require admin consent for applications" standard assigns its own policy, which only lets
        # users consent to the apps it lists: treat that as already locked down.
        $UserConsent.ManagedByCipp = ($SelfPolicies.Count -gt 0 -and -not ($SelfPolicies | Where-Object { $_ -ne 'ManagePermissionGrantsForSelf.cipp-consent-policy' }))
        $UserConsent.Allowed = ($SelfPolicies.Count -gt 0 -and -not $UserConsent.ManagedByCipp)
    } catch { $UserConsent.Error = & $ErrorText $_ }

    # --- Admin consent requests ----------------------------------------------------------------------------
    $Requests = [ordered]@{ Enabled = $null; GlobalAdminsReview = $false; Reviewers = 0; Error = $null }
    try {
        $Policy = New-GraphGetRequest -uri 'https://graph.microsoft.com/beta/policies/adminConsentRequestPolicy' -tenantid $TenantFilter | Select-Object -First 1
        $Requests.Enabled = [bool]($Policy.isEnabled -eq $true -or "$($Policy.isEnabled)" -eq 'true')
        $Requests.Reviewers = @($Policy.reviewers).Count
        $Requests.GlobalAdminsReview = [bool](@($Policy.reviewers) | Where-Object { "$($_.query)" -match $GlobalAdminRoleId })
    } catch { $Requests.Error = & $ErrorText $_ }

    $AppsList = @($Apps)
    $GroupMode = $Group.Exists -and ($AppsList | Where-Object { $_.Assigned.PrincipalId -contains $Group.Id })
    [pscustomobject]@{
        Tenant               = if ($Tenant.defaultDomainName) { $Tenant.defaultDomainName } else { $TenantFilter }
        TenantId             = $TenantId
        Apps                 = $AppsList
        AppsAdded            = -not ($AppsList | Where-Object { -not $_.Exists })
        Consented            = -not ($AppsList | Where-Object { -not $_.Consented })
        Restricted           = -not ($AppsList | Where-Object { -not $_.AssignmentRequired -or $_.Assigned.Count -eq 0 })
        AssignedByGroup      = [bool]$GroupMode
        Group                = [pscustomobject]$Group
        EntraP1              = $EntraP1
        Readiness            = $Readiness
        Access               = [pscustomobject]$Access
        UserConsent          = [pscustomobject]$UserConsent
        AdminConsentRequests = [pscustomobject]$Requests
    }
}
