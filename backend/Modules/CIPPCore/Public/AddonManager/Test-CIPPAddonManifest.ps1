function Test-CIPPAddonManifest {
    <#
    .SYNOPSIS
        Checks an add-on manifest (addon.json) and returns a list of problems (empty when it is fine).

    .DESCRIPTION
        Required: schema 1; id (lowercase letters, numbers and dashes, 3 to 40 characters, matching -Id
        when given); name; version (x.y.z); cipp.minVersion and cipp.testedWith (x.y.z). Menu entries need
        a title, permissions and a path under /addons/<id>. Endpoint names are letters and numbers.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [string]$Id
    )

    $Problems = [System.Collections.Generic.List[string]]::new()
    $Semver = '^\d+\.\d+\.\d+$'
    $M = $Manifest
    if ("$($M.schema)" -ne '1') { $Problems.Add('schema must be 1.') }
    if ("$($M.id)" -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') { $Problems.Add('id must be 3-40 lowercase letters, numbers and dashes.') }
    elseif ($Id -and $M.id -ne $Id) { $Problems.Add("id '$($M.id)' doesn't match its folder '$Id'.") }
    if (-not "$($M.name)".Trim()) { $Problems.Add('name is missing.') }
    if ("$($M.version)" -notmatch $Semver) { $Problems.Add('version must look like 1.2.3.') }
    if ("$($M.cipp.minVersion)" -notmatch $Semver) { $Problems.Add('cipp.minVersion must look like 11.0.0.') }
    $Tested = @($M.cipp.testedWith | Where-Object { $_ })
    if ($Tested.Count -eq 0) { $Problems.Add('cipp.testedWith must list at least one CIPP version.') }
    foreach ($V in $Tested) { if ("$V" -notmatch $Semver) { $Problems.Add("cipp.testedWith has '$V', which isn't a version like 11.2.1.") } }
    foreach ($Item in @($M.menu)) {
        if (-not $Item) { continue }
        if (-not "$($Item.title)".Trim()) { $Problems.Add('A menu entry has no title.') }
        if (@($Item.permissions | Where-Object { $_ }).Count -eq 0) { $Problems.Add("Menu entry '$($Item.title)' has no permissions.") }
        if ("$($Item.path)" -notmatch "^/addons/$([regex]::Escape("$($M.id)"))(/[a-z0-9-]+)*$") { $Problems.Add("Menu entry '$($Item.title)' must have a path under /addons/$($M.id).") }
    }
    foreach ($E in @($M.endpoints)) { if ($E -and "$E" -notmatch '^[A-Za-z][A-Za-z0-9]{2,80}$') { $Problems.Add("Endpoint '$E' isn't a valid name.") } }
    @($Problems)
}
