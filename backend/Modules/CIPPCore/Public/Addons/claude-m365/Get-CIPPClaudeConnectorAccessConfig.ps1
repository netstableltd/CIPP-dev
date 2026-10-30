function Get-CIPPClaudeConnectorAccessConfig {
    <#
    .SYNOPSIS
        The Claude for Microsoft 365 access options: what Claude can read (readAreas) and the four access
        levels (levels), each with its Microsoft Graph scopes. From Config/Addons/claude-m365/ClaudeConnectorAccess.json (the add-on's own settings).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ClaudeConnectorAccessConfig) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../../..' }
        $Path = Join-Path $Root 'Config/Addons/claude-m365/ClaudeConnectorAccess.json'
        $script:ClaudeConnectorAccessConfig = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    $script:ClaudeConnectorAccessConfig
}
