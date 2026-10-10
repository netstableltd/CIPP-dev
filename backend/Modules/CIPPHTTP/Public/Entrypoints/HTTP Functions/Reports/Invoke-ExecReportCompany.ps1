function Invoke-ExecReportCompany {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.ReadWrite
    .DESCRIPTION
        Saves Reports settings for one company (tenant). Only the fields present in the request are changed, so the same endpoint serves the edit dialog and bulk actions such as enabling reporting. Action=Enable or Action=Disable is a shortcut for Enabled.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body

    function Get-FieldValue($Field) {
        if ($null -eq $Field) { return $null }
        if ($Field -is [System.Collections.IDictionary]) {
            if ($Field.Contains('value')) { return $Field['value'] }
            return $Field
        }
        if ($Field.PSObject.Properties.Name -contains 'value') { return $Field.value }
        return $Field
    }
    function Test-Field($Name) {
        if ($Body -is [System.Collections.IDictionary]) { return $Body.Contains($Name) }
        return [bool]($Body.PSObject.Properties.Name -contains $Name)
    }

    $TenantId = "$(Get-FieldValue $Body.TenantId)"
    if (-not $TenantId) { $TenantId = "$(Get-FieldValue $Body.tenantFilter)" }
    $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -eq $TenantId -or $_.defaultDomainName -eq $TenantId } | Select-Object -First 1
    if (-not $Tenant) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "Unknown tenant '$TenantId'." } })
    }
    if (-not (Test-CIPPReportAccess -Request $Request -Tenant $Tenant)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'You do not have access to this tenant.' } })
    }

    $Errors = [System.Collections.Generic.List[string]]::new()
    $EmailPattern = '^[^@\s]+@[^@\s]+\.[^@\s]+$'
    $Changes = @{}

    $Action = "$(Get-FieldValue $Body.Action)"
    if ($Action -eq 'Enable') { $Changes.Enabled = $true }
    elseif ($Action -eq 'Disable') { $Changes.Enabled = $false }
    elseif (Test-Field 'Enabled') { $Changes.Enabled = [bool](Get-FieldValue $Body.Enabled) }

    foreach ($Name in @('Recipients', 'PrecheckRecipients')) {
        if (Test-Field $Name) {
            $List = @("$(Get-FieldValue $Body.$Name)" -split '[,;\s]+' | Where-Object { $_ })
            foreach ($Address in $List) { if ($Address -notmatch $EmailPattern) { $Errors.Add("'$Address' is not a valid email address.") } }
            $Changes[$Name] = ($List -join ', ')
        }
    }

    if (Test-Field 'DeliveryMode') {
        $Value = "$(Get-FieldValue $Body.DeliveryMode)"
        if ($Value -notin @('Default', 'Review', 'Auto', 'Manual')) { $Errors.Add('Delivery must be Default, Review, Auto or Manual.') } else { $Changes.DeliveryMode = $Value }
    }

    if (Test-Field 'ScheduleMode') {
        $Value = "$(Get-FieldValue $Body.ScheduleMode)"
        if ($Value -notin @('Default', 'Custom', 'Manual', 'Paused')) { $Errors.Add('Schedule must be Default, Custom, Manual or Paused.') } else { $Changes.ScheduleMode = $Value }
    }

    if (Test-Field 'ReportDay') {
        $Day = 0
        $Raw = "$(Get-FieldValue $Body.ReportDay)"
        if ($Raw -and (-not [int]::TryParse($Raw, [ref]$Day) -or $Day -lt 1 -or $Day -gt 28)) { $Errors.Add('Report day must be between 1 and 28.') } else { $Changes.ReportDay = [int]$Day }
    }
    if ($Changes.ScheduleMode -eq 'Custom' -and -not $Changes.ReportDay) {
        $Errors.Add('A custom schedule needs a report day (1-28).')
    }

    if (Test-Field 'PausedUntil') {
        $Raw = Get-FieldValue $Body.PausedUntil
        if ($Raw) {
            $Parsed = $null
            # datePicker sends unix seconds; accept ISO dates too.
            if ("$Raw" -match '^\d{9,11}$') { $Parsed = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Raw).UtcDateTime }
            elseif (-not [datetime]::TryParse("$Raw", [ref]$Parsed)) { $Errors.Add('Paused until must be a date.') }
            if ($Parsed) { $Changes.PausedUntil = $Parsed.ToString('yyyy-MM-dd') }
        } else {
            $Changes.PausedUntil = ''
        }
    }
    if ($Changes.ScheduleMode -eq 'Paused' -and -not $Changes.PausedUntil) {
        $Errors.Add('A paused schedule needs a "paused until" date.')
    }

    if (Test-Field 'Notes') { $Changes.Notes = "$(Get-FieldValue $Body.Notes)".Trim() }

    # Ordered sections for this company's main report; an empty list means "use the default sections".
    if (Test-Field 'Sections') {
        $SectionIds = @(ConvertFrom-CIPPReportSectionList $Body.Sections)
        foreach ($Id in $SectionIds) { if (-not (Test-CIPPReportSectionId $Id)) { $Errors.Add("'$Id' is not a known report section.") } }
        $Changes.Sections = if ($SectionIds.Count -gt 0) { ConvertTo-Json -InputObject @($SectionIds) -Compress } else { '' }
    }

    if ($Errors.Count -gt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "$($Tenant.displayName): $($Errors -join ' ')" } })
    }
    if ($Changes.Count -eq 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'Nothing to change.' } })
    }

    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }

    try {
        $Table = Get-CIPPTable -TableName 'ReportCompanies'
        $Existing = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Company' and RowKey eq '$($Tenant.customerId)'"
        $Entity = @{
            PartitionKey = 'Company'
            RowKey       = "$($Tenant.customerId)"
            Domain       = "$($Tenant.defaultDomainName)"
        }
        if ($Existing) {
            foreach ($Prop in $Existing.PSObject.Properties) {
                if ($Prop.Name -notin @('PartitionKey', 'RowKey', 'Timestamp', 'ETag', 'odata.etag')) { $Entity[$Prop.Name] = $Prop.Value }
            }
        }
        foreach ($Key in $Changes.Keys) { $Entity[$Key] = $Changes[$Key] }
        $Entity.ModifiedBy = "$User"
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force

        $Message = "$($Tenant.displayName): report settings updated ($(@($Changes.Keys | Sort-Object) -join ', '))."
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -tenantId $Tenant.customerId -message $Message -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "$($Tenant.displayName): failed to save report settings: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant $Tenant.defaultDomainName -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Message }
        })
}
