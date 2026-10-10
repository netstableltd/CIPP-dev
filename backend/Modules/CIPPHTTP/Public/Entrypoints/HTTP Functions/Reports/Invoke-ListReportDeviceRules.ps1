function Invoke-ListReportDeviceRules {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.Read
    .DESCRIPTION
        Returns the device rules used to rate computers in Reports (Good / Check / Needs attention): every rule with its current and default thresholds.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = Get-CIPPReportDeviceRules
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to read device rules: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to read device rules: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
