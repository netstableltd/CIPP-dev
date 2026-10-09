function Invoke-ExecReportSettings {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.ReadWrite
    .DESCRIPTION
        Saves the global Reports settings. Validates addresses, schedule values and delivery mode before writing.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body

    # Autocomplete fields arrive as { label, value } objects; plain values pass through.
    function Get-FieldValue($Field) {
        if ($null -eq $Field) { return $null }
        if ($Field -is [System.Collections.IDictionary]) {
            if ($Field.Contains('value')) { return $Field['value'] }
            return $Field
        }
        if ($Field.PSObject.Properties.Name -contains 'value') { return $Field.value }
        return $Field
    }

    $Errors = [System.Collections.Generic.List[string]]::new()
    $EmailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'

    $Recipients = @("$(Get-FieldValue $Body.PrecheckRecipients)" -split '[,;\s]+' | Where-Object { $_ })
    foreach ($Address in $Recipients) {
        if ($Address -notmatch $EmailPattern) { $Errors.Add("'$Address' is not a valid email address.") }
    }

    $ReportDayMode = "$(Get-FieldValue $Body.ReportDayMode)"
    if ($ReportDayMode -notin @('FirstWorkingDay', 'DayOfMonth')) { $Errors.Add('Report day must be "First working day" or "Day of month".') }

    $ReportDay = 1
    if (-not [int]::TryParse("$(Get-FieldValue $Body.ReportDay)", [ref]$ReportDay) -or $ReportDay -lt 1 -or $ReportDay -gt 28) {
        if ($ReportDayMode -eq 'DayOfMonth') { $Errors.Add('Day of month must be between 1 and 28.') } else { $ReportDay = 1 }
    }

    $LeadDays = 5
    if (-not [int]::TryParse("$(Get-FieldValue $Body.PrecheckLeadDays)", [ref]$LeadDays) -or $LeadDays -lt 1 -or $LeadDays -gt 20) {
        $Errors.Add('Pre-check lead time must be between 1 and 20 days.')
    }

    $SendTime = "$(Get-FieldValue $Body.SendTime)"
    if ($SendTime -notmatch '^([01]\d|2[0-3]):[0-5]\d$') { $Errors.Add('Send time must be in HH:mm (24-hour) format.') }

    $TimeZone = "$(Get-FieldValue $Body.TimeZone)"
    try { $null = [System.TimeZoneInfo]::FindSystemTimeZoneById($TimeZone) } catch { $Errors.Add("'$TimeZone' is not a recognised time zone.") }

    $DeliveryMode = "$(Get-FieldValue $Body.DefaultDeliveryMode)"
    if ($DeliveryMode -notin @('Review', 'Auto', 'Manual')) { $Errors.Add('Default delivery must be Review, Auto or Manual.') }

    if ($Errors.Count -gt 0) {
        return ([HttpResponseContext]@{
                StatusCode = [HttpStatusCode]::BadRequest
                Body       = @{ Results = ($Errors -join ' ') }
            })
    }

    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }

    $Entity = @{
        PartitionKey        = 'Settings'
        RowKey              = 'Global'
        PrecheckRecipients  = ($Recipients -join ', ')
        ReportDayMode       = $ReportDayMode
        ReportDay           = [int]$ReportDay
        PrecheckLeadDays    = [int]$LeadDays
        SendTime            = $SendTime
        TimeZone            = $TimeZone
        DefaultDeliveryMode = $DeliveryMode
        CustomerSendEnabled = [bool]$Body.CustomerSendEnabled
        ModifiedBy          = "$User"
    }

    try {
        $Table = Get-CIPPTable -TableName 'ReportSettings'
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force
        $Message = 'Report settings saved.'
        if ($Entity.CustomerSendEnabled) { $Message += ' Sending to customer recipients is ENABLED.' }
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Message -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to save report settings: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Message }
        })
}
