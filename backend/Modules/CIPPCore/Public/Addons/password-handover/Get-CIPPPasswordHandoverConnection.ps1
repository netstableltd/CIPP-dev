function Get-CIPPPasswordHandoverConnection {
    <#
    .SYNOPSIS
        The Password Pusher server to use: the add-on's own server address if one is saved, otherwise
        the server in CIPP's Password Pusher integration (Settings > Integrations).

    .DESCRIPTION
        The integration's API key and Cloudflare Access settings are used only when the server is the
        integration's own; a different address saved in the add-on is used without them (anonymous
        pushes). Either way the add-on applies its own expiry settings, and the integration doesn't
        need to be switched on. With -StatusOnly it only says which server it would use, without
        contacting it.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$ServerUrl,
        [switch]$StatusOnly
    )

    $Config = $null
    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Entity = Get-CIPPAzDataTableEntity @Table
        if ($Entity.config) { $Config = $Entity.config | ConvertFrom-Json -ErrorAction Stop }
    } catch {
        $Config = $null
    }
    $PwPush = $Config.PWPush
    $IntegrationUrl = "$($PwPush.BaseUrl)".Trim().TrimEnd('/')
    $Own = "$ServerUrl".Trim().TrimEnd('/')
    $BaseUrl = if ($Own) { $Own } else { $IntegrationUrl }
    $UsesIntegration = [bool]$BaseUrl -and $BaseUrl -eq $IntegrationUrl
    $Authenticated = $UsesIntegration -and ($PwPush.UseBearerAuth -eq $true -or -not [string]::IsNullOrEmpty($PwPush.EmailAddress))

    if ($StatusOnly) {
        return [pscustomobject]@{
            Configured         = [bool]$BaseUrl
            BaseUrl            = $BaseUrl
            Source             = if (-not $BaseUrl) { 'none' } elseif ($Own) { 'addon' } else { 'integration' }
            Authenticated      = $Authenticated
            IntegrationUrl     = $IntegrationUrl
            IntegrationEnabled = ($PwPush.Enabled -eq $true)
        }
    }

    if (-not $BaseUrl) { throw 'Set up Password Pusher first: give its address on the Password hand-over page, or in Settings > Integrations > Password Pusher.' }
    if ($BaseUrl -notmatch '^https://') { throw 'The Password Pusher address must start with https://.' }

    $Headers = @{ Accept = 'application/json' }
    if ($UsesIntegration -and $PwPush.CFEnabled -eq $true -and $Config.CFZTNA.Enabled -eq $true) {
        $Headers['CF-Access-Client-Id'] = "$($Config.CFZTNA.ClientId)"
        $Headers['CF-Access-Client-Secret'] = "$(Get-ExtensionAPIKey -Extension 'CFZTNA')"
    }
    $Version = Get-CIPPPwPushVersion -BaseUrl $BaseUrl -Headers $Headers
    if ($Authenticated) {
        $ApiKey = Get-ExtensionAPIKey -Extension 'PWPush'
        if (-not [string]::IsNullOrEmpty($ApiKey)) { $Headers['Authorization'] = "Bearer $ApiKey" }
    }
    $WorkspaceId = if ($Authenticated -and $PwPush.UseBearerAuth -eq $true -and -not [string]::IsNullOrEmpty($PwPush.AccountId.value)) { [string]$PwPush.AccountId.value }

    [pscustomobject]@{
        BaseUrl     = $BaseUrl
        Headers     = $Headers
        ApiVersion  = $Version.ApiVersion
        WorkspaceId = $WorkspaceId
    }
}
