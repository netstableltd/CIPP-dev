function Invoke-ListReportCompanies {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.Read
    .DESCRIPTION
        Lists every tenant as a Reports company: whether reporting is on, recipients, delivery and schedule modes (with the effective values after applying global defaults), Atera mapping and data status. Pass TenantId for a single company.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = @(Get-CIPPReportCompanies -TenantId $Request.Query.TenantId)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Failed to list report companies: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        $Body = @{ Results = "Failed to list report companies: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
