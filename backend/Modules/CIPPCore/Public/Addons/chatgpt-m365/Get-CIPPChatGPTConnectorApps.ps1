function Get-CIPPChatGPTConnectorApps {
    <#
    .SYNOPSIS
        The Microsoft Entra app behind OpenAI's ChatGPT connectors for Microsoft 365.

    .DESCRIPTION
        Used by the ChatGPT for Microsoft 365 standard process (Community Additions).
        One multi-tenant app, 'ChatGPT' (verified publisher OpenAI, L.L.C., owner tenant
        a48cca56-e6da-484e-a814-9c849652bcb3), carries every Microsoft connector: Outlook Email, Outlook
        Calendar, Teams and SharePoint/OneDrive. Each connector's consent adds its scopes to the same
        Microsoft Graph grant. OpenAI doesn't publish the app id; it was confirmed from the service
        principals in managed tenants in November 2026.

        Not covered here: the separate @ChatGPT Teams bot (Entra app 1f5363a7-8b93-4af5-acfa-f7379830d480,
        set up from ChatGPT's admin console > Agents with resource-specific consent) and the ChatGPT iOS
        app for Intune.

        Returned as a list (like the Claude add-on) so a second app can be added if OpenAI splits it.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    @(
        [pscustomobject]@{ Key = 'ChatGPT'; Name = 'ChatGPT'; AppId = 'e0476654-c1d5-430b-ab80-70cbd947616a'; Publisher = 'OpenAI, L.L.C.' }
    )
}
