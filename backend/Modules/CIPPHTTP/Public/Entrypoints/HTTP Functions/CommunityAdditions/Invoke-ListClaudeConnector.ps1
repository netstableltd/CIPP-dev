function Invoke-ListClaudeConnector {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Tenant.Application.Read
    .DESCRIPTION
        Community Additions > Standard Processes > Claude for Microsoft 365: how far the tenant (tenantFilter) is through setting up Anthropic's Claude connector. Read-only. Also returns what the tenant already has (Readiness: backup, Entra ID P1, Defender, Business Premium), what Claude can read and change (Access) the options (Options: read areas and access levels) and the uploaded connection guide, if any (Guide). GroupName is the access group to look for (default SG-Claude-Users).
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $TenantFilter = "$($Request.Query.tenantFilter ?? $Request.Body.tenantFilter)"
    $GroupName = "$($Request.Query.GroupName ?? $Request.Body.GroupName)".Trim()
    if (-not $GroupName) { $GroupName = 'SG-Claude-Users' }

    if (-not $TenantFilter -or $TenantFilter -eq 'AllTenants') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Choose a single tenant.' } })
    }
    if ($GroupName -notmatch '^[A-Za-z0-9 _.\-]{1,120}$') {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'The group name can only use letters, numbers, spaces, dots, dashes and underscores (up to 120).' } })
    }

    try {
        $Status = Get-CIPPClaudeConnectorStatus -TenantFilter $TenantFilter -GroupName $GroupName
        # The read areas and access levels, so the page and the PDF describe the same options.
        $Config = Get-CIPPClaudeConnectorAccessConfig
        $Guide = try { Get-CIPPClaudeConnectorGuide } catch { $null }
        $Status | Add-Member -NotePropertyName Guide -NotePropertyValue $Guide -Force
        $Status | Add-Member -NotePropertyName Options -NotePropertyValue ([pscustomobject]@{ ReadAreas = $Config.readAreas; Levels = $Config.levels; WriteScopes = $Config.writeScopes }) -Force
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $Status })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Couldn't read the Claude connector setup: $($ErrorMessage.NormalizedError)" } })
    }
}
