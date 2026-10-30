function Invoke-ListAddons {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Community Additions > Settings > Add-ons: the add-ons installed in this CIPP (version, whether each is turned on, and whether it is expected to work on this CIPP version: Compatible, Untested, NeedsNewerCipp or Problem, with what is missing), this CIPP's version and the newest upstream CIPP version, and the add-on packages uploaded to this instance.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Status = Get-CIPPAddonStatus
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = $Status })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Couldn't list the add-ons: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Couldn't list the add-ons: $($ErrorMessage.NormalizedError)" } })
    }
}
