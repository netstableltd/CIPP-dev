function Get-CIPPPasswordHandoverConnection {
    <#
    .SYNOPSIS
        The Password Pusher server to use, from CIPP's own Password Pusher integration
        (Settings > Integrations): its address, sign-in and Cloudflare Access settings.

    .DESCRIPTION
        The add-on uses the integration's server and API key but its own link settings, so it works
        whether or not the integration is switched on for CIPP's other password results.
        With -StatusOnly it only says whether a server is set up, without contacting it.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$StatusOnly)

    $Config = $null
    try {
        $Table = Get-CIPPTable -TableName Extensionsconfig
        $Entity = Get-CIPPAzDataTableEntity @Table
        if ($Entity.config) { $Config = $Entity.config | ConvertFrom-Json -ErrorAction Stop }
    } catch {
        $Config = $null
    }
    $PwPush = $Config.PWPush
    $BaseUrl = "$($PwPush.BaseUrl)".Trim().TrimEnd('/')
    $Authenticated = ($PwPush.UseBearerAuth -eq $true -or -not [string]::IsNullOrEmpty($PwPush.EmailAddress))

    if ($StatusOnly) {
        return [pscustomobject]@{
            Configured           = [bool]$BaseUrl
            BaseUrl              = $BaseUrl
            Authenticated        = $Authenticated
            IntegrationEnabled   = ($PwPush.Enabled -eq $true)
        }
    }

    if (-not $BaseUrl) { throw 'Set up Password Pusher first: Settings > Integrations > Password Pusher, with your server address.' }
    if ($BaseUrl -notmatch '^https://') { throw 'The Password Pusher address must start with https://.' }

    $Headers = @{ Accept = 'application/json' }
    if ($PwPush.CFEnabled -eq $true -and $Config.CFZTNA.Enabled -eq $true) {
        $Headers['CF-Access-Client-Id'] = "$($Config.CFZTNA.ClientId)"
        $Headers['CF-Access-Client-Secret'] = "$(Get-ExtensionAPIKey -Extension 'CFZTNA')"
    }
    $Version = Get-CIPPPwPushVersion -BaseUrl $BaseUrl -Headers $Headers
    if ($Authenticated) {
        $ApiKey = Get-ExtensionAPIKey -Extension 'PWPush'
        if (-not [string]::IsNullOrEmpty($ApiKey)) { $Headers['Authorization'] = "Bearer $ApiKey" }
    }
    $WorkspaceId = if ($PwPush.UseBearerAuth -eq $true -and -not [string]::IsNullOrEmpty($PwPush.AccountId.value)) { [string]$PwPush.AccountId.value }

    [pscustomobject]@{
        BaseUrl     = $BaseUrl
        Headers     = $Headers
        ApiVersion  = $Version.ApiVersion
        WorkspaceId = $WorkspaceId
    }
}
