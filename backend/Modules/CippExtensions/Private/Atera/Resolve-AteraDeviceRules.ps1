function Resolve-AteraDeviceRules {
    <#
    .SYNOPSIS
        Device rules as a hashtable of id -> rule: the defaults in Config/DeviceRatingRules.json with -Rules on top.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Rules)

    if (-not $script:AteraDeviceRuleDefaults) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../..' }
        $Path = Join-Path (Join-Path $Root 'Config') 'DeviceRatingRules.json'
        $script:AteraDeviceRuleDefaults = try { @((Get-Content -Path $Path -Raw -ErrorAction Stop | ConvertFrom-Json).rules) } catch { @() }
    }
    $Out = @{}
    foreach ($D in $script:AteraDeviceRuleDefaults) { $Out["$($D.id)"] = $D }
    if ($Rules) {
        $Items = if ($Rules -is [System.Collections.IDictionary]) { @($Rules.Values) } else { @($Rules) }
        foreach ($Rule in $Items) {
            if (-not $Rule -or -not $Rule.id) { continue }
            $Merged = [ordered]@{}
            if ($Out.ContainsKey("$($Rule.id)")) { foreach ($P in $Out["$($Rule.id)"].PSObject.Properties) { $Merged[$P.Name] = $P.Value } }
            $Props = if ($Rule -is [System.Collections.IDictionary]) { $Rule.Keys | ForEach-Object { @{ Name = $_; Value = $Rule[$_] } } } else { $Rule.PSObject.Properties | ForEach-Object { @{ Name = $_.Name; Value = $_.Value } } }
            foreach ($P in $Props) { if ($P.Name -in @('check', 'attention', 'severity', 'value')) { $Merged[$P.Name] = $P.Value } }
            $Merged.id = "$($Rule.id)"
            $Out["$($Rule.id)"] = [pscustomobject]$Merged
        }
    }
    $Out
}
