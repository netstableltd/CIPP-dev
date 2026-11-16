function Invoke-ListPasswordHandover {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Community Additions > Password hand-over (add-on password-handover): the add-on's settings (link days and views, passphrase, the message to the customer and its placeholders) and which Password Pusher server it uses (its own address, or the one in Settings > Integrations). Never returns the API key.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Settings = Get-CIPPPasswordHandoverSettings
        $Server = Get-CIPPPasswordHandoverConnection -ServerUrl $Settings.serverUrl -StatusOnly
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Settings = $Settings; Server = $Server } })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "The settings couldn't be loaded: $($ErrorMessage.NormalizedError)" } })
    }
}
