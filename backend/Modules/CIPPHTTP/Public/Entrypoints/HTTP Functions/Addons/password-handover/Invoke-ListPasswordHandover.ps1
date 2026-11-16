function Invoke-ListPasswordHandover {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        Identity.User.Read
    .DESCRIPTION
        Community Additions > Password hand-over (add-on password-handover): the add-on's settings (link days and views, passphrase, the message to the customer and its placeholders) and whether a Password Pusher server is set up in Settings > Integrations. Never returns the API key.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Settings = Get-CIPPPasswordHandoverSettings
        $Server = Get-CIPPPasswordHandoverConnection -StatusOnly
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Settings = $Settings; Server = $Server } })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "The settings couldn't be loaded: $($ErrorMessage.NormalizedError)" } })
    }
}
