function Invoke-ListReportSettings {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.Read
    .DESCRIPTION
        Returns the global Reports settings (pre-check recipients, default schedule, delivery mode and the customer-send master switch), with defaults for anything not yet saved.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = Get-CIPPReportSettings
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to read report settings: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to read report settings: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
