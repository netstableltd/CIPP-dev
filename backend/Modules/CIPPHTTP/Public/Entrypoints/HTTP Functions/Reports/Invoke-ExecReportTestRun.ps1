function Invoke-ExecReportTestRun {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.ReadWrite
    .DESCRIPTION
        Generates a customer report or pre-check for one company on demand (the Test button). The PDF is stored under Generated Reports and, if SendTo is given, emailed only to those addresses - never to the company's customer recipients. ReportType is Customer or Precheck; Period is LastMonth, ThisMonth or yyyy-MM.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body

    function Get-FieldValue($Field) {
        if ($null -eq $Field) { return $null }
        if ($Field -is [System.Collections.IDictionary]) { if ($Field.Contains('value')) { return $Field['value'] }; return $Field }
        if ($Field.PSObject.Properties.Name -contains 'value') { return $Field.value }
        return $Field
    }

    $TenantId = "$(Get-FieldValue $Body.TenantId)"
    if (-not $TenantId) { $TenantId = "$(Get-FieldValue $Body.tenantFilter)" }
    $ReportType = "$(Get-FieldValue $Body.ReportType)"
    if (-not $ReportType) { $ReportType = 'Customer' }
    $Period = "$(Get-FieldValue $Body.Period)"
    if (-not $Period) { $Period = 'LastMonth' }
    $SendTo = @("$(Get-FieldValue $Body.SendTo)" -split '[,;\s]+' | Where-Object { $_ })

    $Errors = [System.Collections.Generic.List[string]]::new()
    if ($ReportType -notin @('Customer', 'Precheck')) { $Errors.Add('Report type must be Customer or Precheck.') }
    if ($Period -notmatch '^(LastMonth|ThisMonth|\d{4}-\d{2})$') { $Errors.Add('Period must be LastMonth, ThisMonth or yyyy-MM.') }
    foreach ($Address in $SendTo) { if ($Address -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') { $Errors.Add("'$Address' is not a valid email address.") } }
    if ($SendTo.Count -gt 5) { $Errors.Add('Send a test to at most 5 addresses.') }
    if ($Errors.Count -gt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = ($Errors -join ' ') } })
    }

    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }

    try {
        $Result = Invoke-CIPPReportGeneration -TenantFilter $TenantId -ReportType $ReportType -Period $Period -SendTo ($SendTo -join ',') -Test -RequestedBy $User -Headers $Headers
        $StatusCode = [HttpStatusCode]::OK
        $ResponseBody = @{ Results = $Result.Results; ReportGUID = $Result.ReportGUID; Link = $Result.Link }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Test report failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $TenantId -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
        $ResponseBody = @{ Results = $Message }
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = $ResponseBody
        })
}
