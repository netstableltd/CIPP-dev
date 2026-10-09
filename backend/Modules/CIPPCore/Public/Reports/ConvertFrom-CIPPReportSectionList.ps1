function ConvertFrom-CIPPReportSectionList {
    <#
    .SYNOPSIS
        Normalises a stored or submitted section list to an array of section ids.

    .DESCRIPTION
        Accepts a JSON array string (as stored), an array of ids, or an array of autocomplete
        objects ({ label, value }) as posted by the UI. Unknown shapes and blanks are dropped;
        order is kept and duplicates removed.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Value)

    if ($null -eq $Value) { return @() }
    $Items = $Value
    if ($Value -is [string]) {
        if ([string]::IsNullOrWhiteSpace($Value)) { return @() }
        try { $Items = @($Value | ConvertFrom-Json -ErrorAction Stop) } catch { $Items = @($Value -split '[,;]') }
    }
    $Seen = [System.Collections.Generic.HashSet[string]]::new()
    $Out = [System.Collections.Generic.List[string]]::new()
    foreach ($Item in @($Items)) {
        $Id = if ($Item -is [string]) { $Item }
        elseif ($Item -is [System.Collections.IDictionary]) { [string]$Item['value'] }
        elseif ($Item.PSObject.Properties.Name -contains 'value') { [string]$Item.value }
        else { "$Item" }
        $Id = "$Id".Trim()
        if ($Id -and $Seen.Add($Id)) { $Out.Add($Id) }
    }
    return @($Out)
}
