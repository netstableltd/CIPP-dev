function Test-CIPPAddonCompatibility {
    <#
    .SYNOPSIS
        Whether an add-on can be expected to work on this CIPP version.

    .DESCRIPTION
        Status, worst first:
          Problem          the manifest is invalid, or something the add-on uses from CIPP (dependsOn.functions)
                           or one of its own endpoints isn't in this CIPP. Upstream removed or renamed it.
          NeedsNewerCipp   this CIPP is older than cipp.minVersion.
          Untested         nothing is missing, but the add-on hasn't been tested on this CIPP version
                           (major.minor isn't in cipp.testedWith). Check it before relying on it.
          Compatible       tested on this CIPP's major.minor version and nothing is missing.

        Functions and endpoints are looked up with Get-Command, so this checks the CIPP actually running.
        -SkipRuntimeCheck skips that (for checking an uploaded package against a version only).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Manifest,
        [string]$CippVersion,
        [switch]$SkipRuntimeCheck
    )

    $Errors = @($Manifest.ManifestErrors | Where-Object { $_ })
    if ($Errors.Count -eq 0 -and $Manifest.schema) { $Errors = @(Test-CIPPAddonManifest -Manifest $Manifest) }
    $MissingFunctions = @(); $MissingEndpoints = @()
    if (-not $SkipRuntimeCheck) {
        $MissingFunctions = @($Manifest.dependsOn.functions | Where-Object { $_ -and -not (Get-Command -Name $_ -ErrorAction SilentlyContinue) })
        $MissingEndpoints = @($Manifest.endpoints | Where-Object { $_ -and -not (Get-Command -Name "Invoke-$_" -ErrorAction SilentlyContinue) })
    }
    $Tested = @($Manifest.cipp.testedWith | Where-Object { $_ })
    $MajorMinor = { param($V) (("$V" -split '[+\-\s]')[0] -split '\.')[0..1] -join '.' }
    $TestedHere = $CippVersion -and ($Tested | Where-Object { (& $MajorMinor $_) -eq (& $MajorMinor $CippVersion) })
    $Newest = $Tested | Sort-Object { [version](("$_" -split '[+\-\s]')[0]) } | Select-Object -Last 1

    $Status, $Message = if ($Errors.Count -gt 0) {
        'Problem', "The add-on's manifest has problems: $($Errors -join ' ')"
    } elseif ($MissingFunctions.Count -gt 0 -or $MissingEndpoints.Count -gt 0) {
        $Parts = @()
        if ($MissingFunctions.Count) { $Parts += "CIPP functions it uses are missing: $($MissingFunctions -join ', ')" }
        if ($MissingEndpoints.Count) { $Parts += "its own endpoints aren't loaded: $($MissingEndpoints -join ', ')" }
        'Problem', ("$($Parts -join '; ')." -replace '^.', { $_.Value.ToUpper() })
    } elseif (-not $CippVersion) {
        'Untested', "This CIPP's version couldn't be read."
    } elseif ((Compare-CIPPVersion $CippVersion $Manifest.cipp.minVersion) -lt 0) {
        'NeedsNewerCipp', "Needs CIPP $($Manifest.cipp.minVersion) or later; this is $CippVersion."
    } elseif ($TestedHere) {
        'Compatible', "Tested on CIPP $(& $MajorMinor $CippVersion)."
    } else {
        'Untested', "Not yet tested on CIPP $CippVersion (last tested on $Newest). Nothing it uses is missing; check it before relying on it."
    }
    [pscustomobject]@{
        Status           = $Status
        Message          = $Message
        MissingFunctions = $MissingFunctions
        MissingEndpoints = $MissingEndpoints
        ManifestErrors   = $Errors
        TestedHere       = [bool]$TestedHere
    }
}
