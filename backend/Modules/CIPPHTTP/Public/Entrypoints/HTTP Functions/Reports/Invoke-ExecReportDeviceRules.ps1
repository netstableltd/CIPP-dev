function Invoke-ExecReportDeviceRules {
    <#
    .FUNCTIONALITY
        Entrypoint, AnyTenant
    .ROLE
        CIPP.Reports.ReadWrite
    .DESCRIPTION
        Saves the device rules used to rate computers in Reports. Body: { Rules: [ { id, check, attention, severity, value } ] }, or { Action: 'Reset' } to go back to the defaults. Only known rule ids and fields are stored; a blank threshold means the rule never triggers at that level.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body

    if (-not (Test-CIPPReportAccess -Request $Request -AllTenants)) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::Forbidden; Body = @{ Results = 'Device rules apply to every company, so changing them needs access to all tenants.' } })
    }

    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }

    $Table = Get-CIPPTable -TableName 'ReportSettings'
    if ("$($Body.Action)" -eq 'Reset') {
        try {
            $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Settings' and RowKey eq 'DeviceRules'"
            if ($Row) { Remove-AzDataTableEntity -Force @Table -Entity $Row }
            Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'Device rules reset to the defaults.' -Sev 'Info'
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = 'Device rules reset to the defaults.' } })
        } catch {
            $ErrorMessage = Get-CippException -Exception $_
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "Failed to reset device rules: $($ErrorMessage.NormalizedError)" } })
        }
    }

    $Known = @{}
    foreach ($Rule in @((Get-CIPPReportDeviceRules).Rules)) { $Known["$($Rule.id)"] = $Rule }

    $Errors = [System.Collections.Generic.List[string]]::new()
    $ToNumber = {
        param($Value, $Label)
        if ($null -eq $Value -or "$Value".Trim() -eq '') { return $null }
        $N = 0.0
        if (-not [double]::TryParse("$Value", [System.Globalization.NumberStyles]::Float, [cultureinfo]::InvariantCulture, [ref]$N) -or $N -lt 0 -or $N -gt 100000) {
            $Errors.Add("$Label must be a number of 0 or more (or blank).")
            return $null
        }
        $N
    }

    $Save = foreach ($Rule in @($Body.Rules)) {
        $Id = "$($Rule.id)"
        if (-not $Known.ContainsKey($Id)) { continue }
        $Def = $Known[$Id]
        $Out = [ordered]@{ id = $Id }
        switch ("$($Def.kind)") {
            'flag' {
                $Severity = "$($Rule.severity)"
                if ($Severity -notin @('attention', 'check', 'off')) { $Errors.Add("$($Def.label): choose Needs attention, Check or Off.") }
                $Out.severity = $Severity
            }
            'setting' {
                $V = & $ToNumber $Rule.value $Def.label
                if ($null -eq $V) { $Errors.Add("$($Def.label) needs a value.") }
                $Out.value = $V
            }
            default {
                $Out.check = & $ToNumber $Rule.check "$($Def.label) (Check)"
                $Out.attention = & $ToNumber $Rule.attention "$($Def.label) (Needs attention)"
            }
        }
        [pscustomobject]$Out
    }
    $Save = @($Save)
    $Values = @{}; foreach ($S in $Save) { $Values[$S.id] = $S }
    $Setting = { param($Id) if ($Values.ContainsKey($Id)) { $Values[$Id].value } else { $Known[$Id].value } }
    $Start = & $Setting 'workdayStart'; $End = & $Setting 'workdayEnd'; $Mem = & $Setting 'memoryThreshold'
    if ($null -ne $Start -and ($Start -lt 0 -or $Start -gt 23)) { $Errors.Add('Working day starts must be an hour from 0 to 23.') }
    if ($null -ne $End -and ($End -lt 1 -or $End -gt 24)) { $Errors.Add('Working day ends must be an hour from 1 to 24.') }
    if ($null -ne $Start -and $null -ne $End -and $End -le $Start) { $Errors.Add('The working day must end after it starts.') }
    if ($null -ne $Mem -and ($Mem -lt 1 -or $Mem -gt 100)) { $Errors.Add('High memory threshold must be between 1 and 100%.') }
    if ($Errors.Count -gt 0) {
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = ($Errors -join ' ') } })
    }

    try {
        Add-CIPPAzDataTableEntity @Table -Force -Entity @{
            PartitionKey = 'Settings'
            RowKey       = 'DeviceRules'
            Rules        = [string](ConvertTo-Json -InputObject $Save -Compress -Depth 3)
            ModifiedBy   = "$User"
        }
        $Message = 'Device rules saved. Reports use them from the next report; the device list in the Report Builder updates at the next Atera sync.'
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message 'Device rules saved.' -Sev 'Info'
        $StatusCode = [HttpStatusCode]::OK
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Failed to save device rules: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -headers $Headers -API $APIName -tenant 'Global' -message $Message -Sev 'Error' -LogData $ErrorMessage
        $StatusCode = [HttpStatusCode]::InternalServerError
    }

    return ([HttpResponseContext]@{
            StatusCode = $StatusCode
            Body       = @{ Results = $Message }
        })
}
