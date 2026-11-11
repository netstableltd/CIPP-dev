function Get-CIPPChatGPTConnectorAccessConfig {
    <#
    .SYNOPSIS
        The ChatGPT for Microsoft 365 access options: what ChatGPT can read (readAreas) and the four access
        levels (levels), each with its Microsoft Graph scopes. From Config/Addons/chatgpt-m365/ChatGPTConnectorAccess.json (the add-on's own settings).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:ChatGPTConnectorAccessConfig) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../../..' }
        $Path = Join-Path $Root 'Config/Addons/chatgpt-m365/ChatGPTConnectorAccess.json'
        $script:ChatGPTConnectorAccessConfig = Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json
    }
    $script:ChatGPTConnectorAccessConfig
}
