function Invoke-ListReportSections {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.Read
    .DESCRIPTION
        Lists the sections a company's main report can include: the built-in customer report sections and every Report Builder template (value 'template:<GUID>').
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    try {
        $Body = @(Get-CIPPReportSectionCatalog)
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Body = @{ Results = "Failed to list report sections: $($ErrorMessage.NormalizedError)" }
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $Body
        })
}
