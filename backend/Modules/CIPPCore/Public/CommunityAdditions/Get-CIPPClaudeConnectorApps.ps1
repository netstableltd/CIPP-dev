function Get-CIPPClaudeConnectorApps {
    <#
    .SYNOPSIS
        The two Microsoft Entra apps behind Anthropic's Claude connector for Microsoft 365.

    .DESCRIPTION
        Used by the Claude for Microsoft 365 standard process (Community Additions > Standard Processes).
        Both apps are multi-tenant apps published by Anthropic; a tenant needs a service principal for
        each, tenant-wide admin consent on each, and (to limit who can use Claude) user assignment
        required on both.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Key = 'Client'; Name = 'M365 MCP Client for Claude'; AppId = '08ad6f98-a4f8-4635-bb8d-f1a3044760f0' }
        [pscustomobject]@{ Key = 'Server'; Name = 'M365 MCP Server for Claude'; AppId = '07c030f6-5743-41b7-ba00-0a6e85f37c17' }
    )
}
