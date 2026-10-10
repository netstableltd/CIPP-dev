function Get-CIPPReportDeviceRules {
    <#
    .SYNOPSIS
        Returns the device rules used to rate computers in Reports (Good / Check / Needs attention).

    .DESCRIPTION
        Defaults come from Config/DeviceRatingRules.json. Changes saved under Reports > Device Rules are
        stored as one row in the ReportSettings table (PartitionKey 'Settings', RowKey 'DeviceRules') and
        replace the matching default's thresholds. Returns every rule, in the defaults' order, with
        IsDefault showing whether it still has its default values.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
    $Path = Join-Path (Join-Path $Root 'Config') 'DeviceRatingRules.json'
    $Defaults = @((Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json).rules)

    $Saved = @{}
    $Row = $null
    try {
        $Table = Get-CIPPTable -TableName 'ReportSettings'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Settings' and RowKey eq 'DeviceRules'"
        if ($Row -and $Row.Rules) {
            foreach ($S in @($Row.Rules | ConvertFrom-Json -ErrorAction Stop)) { if ($S.id) { $Saved["$($S.id)"] = $S } }
        }
    } catch {
        Write-Information "Device rules: using defaults ($($_.Exception.Message))"
    }

    $Rules = foreach ($D in $Defaults) {
        $Rule = [ordered]@{}
        foreach ($P in $D.PSObject.Properties) { $Rule[$P.Name] = $P.Value }
        $Rule.default = [ordered]@{ check = $D.check; attention = $D.attention; severity = $D.severity; value = $D.value }
        $IsDefault = $true
        if ($Saved.ContainsKey("$($D.id)")) {
            $S = $Saved["$($D.id)"]
            foreach ($Name in @('check', 'attention', 'severity', 'value')) {
                if ($S.PSObject.Properties.Name -contains $Name -and $D.PSObject.Properties.Name -contains $Name) {
                    if ("$($S.$Name)" -ne "$($D.$Name)") { $IsDefault = $false }
                    $Rule[$Name] = $S.$Name
                }
            }
        }
        $Rule.isDefault = $IsDefault
        [pscustomobject]$Rule
    }

    [pscustomobject]@{
        Rules          = @($Rules)
        LastModified   = $(if ($Row) { $Row.Timestamp } else { $null })
        LastModifiedBy = $(if ($Row) { $Row.ModifiedBy } else { $null })
    }
}
