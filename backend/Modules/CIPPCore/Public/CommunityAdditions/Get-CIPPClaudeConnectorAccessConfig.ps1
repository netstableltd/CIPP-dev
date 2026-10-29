function Get-CIPPClaudeConnectorAccessConfig {
    <#
    .SYNOPSIS
        The Claude for Microsoft 365 access options: what Claude can read (readAreas) and the four access
        levels (levels), each with its Microsoft Graph scopes. From Config/ClaudeConnectorAccess.json.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ClaudeConnectorAccessConfig) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
        $Path = Join-Path (Join-Path $Root 'Config') 'ClaudeConnectorAccess.json'
        $script:ClaudeConnectorAccessConfig = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    $script:ClaudeConnectorAccessConfig
}
