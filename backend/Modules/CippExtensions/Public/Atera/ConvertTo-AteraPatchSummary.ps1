function ConvertTo-AteraPatchSummary {
    <#
    .SYNOPSIS
        Summarises Atera's patch scan for one device (installed-patches + available-patches endpoints).

    .DESCRIPTION
        Atera's patch scan lists the Microsoft updates a device has installed (with dates) and the ones it
        still needs (status Available or Failed): Windows cumulative and security updates, .NET, Office
        (when Microsoft Update is on), drivers and Defender definitions. Defender definition updates are
        ignored - they arrive several times a day and are never "behind" in a way that matters here.

        Output fields: PatchScanDate, SecurityUpdatesWaiting, OtherUpdatesWaiting (not security, not
        drivers), DriverUpdatesWaiting, UpdatesFailed / SecurityUpdatesFailed (not drivers), DriversFailed,
        LastSecurityUpdate (yyyy-MM-dd; the Malicious Software Removal Tool doesn't count), UpdatesWaiting
        (security and other updates, security first, '; '-joined), DriversWaiting, UpdatesFailing (not
        drivers), DriversFailing. Driver updates are optional, so a failed driver is listed but not a
        problem.

    .PARAMETER Installed
        Response of GET agents/{deviceGuid}/installed-patches.

    .PARAMETER Available
        Response of GET agents/{deviceGuid}/available-patches.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Installed, $Available)

    $SecurityClasses = @('Security Updates', 'Critical Updates', 'Update Rollups')
    $Waiting = @(@($Available.availableUpdates) | Where-Object { $_ -and "$($_.class)" -ne 'Definition Updates' })
    $Failed = @($Waiting | Where-Object { "$($_.status)" -eq 'Failed' })
    $FailedDrivers = @($Failed | Where-Object { "$($_.class)" -match 'driver' })
    $FailedOther = @($Failed | Where-Object { "$($_.class)" -notmatch 'driver' })
    $Pending = @($Waiting | Where-Object { "$($_.status)" -ne 'Failed' })
    $Security = @($Pending | Where-Object { "$($_.class)" -in $SecurityClasses })
    $Drivers = @($Pending | Where-Object { "$($_.class)" -match 'driver' })
    $Other = @($Pending | Where-Object { "$($_.class)" -notin $SecurityClasses -and "$($_.class)" -notmatch 'driver' })
    # The monthly Malicious Software Removal Tool is filed as an update rollup but is not a security patch.
    $LastSecurity = @(@($Installed.installedUpdates) | Where-Object { $_ -and "$($_.class)" -in $SecurityClasses -and $_.installDate -and "$($_.name)" -notmatch 'Malicious Software Removal Tool' } | ForEach-Object {
            $d = [datetime]::MinValue
            if ($_.installDate -is [datetime]) { $_.installDate.ToUniversalTime() }
            elseif ([datetime]::TryParse("$($_.installDate)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$d)) { $d }
        } | Sort-Object -Descending | Select-Object -First 1)
    $Scan = if ($Available.timestamp) { $Available.timestamp } elseif ($Installed.timestamp) { $Installed.timestamp } else { $null }
    $ScanDate = $null
    if ($Scan -is [datetime]) { $ScanDate = $Scan.ToUniversalTime() } elseif ($Scan) { $p = [datetime]::MinValue; if ([datetime]::TryParse("$Scan", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$p)) { $ScanDate = $p } }

    [pscustomobject]@{
        PatchScanDate          = $(if ($ScanDate) { $ScanDate.ToString('yyyy-MM-ddTHH:mm:ssZ') } else { '' })
        SecurityUpdatesWaiting = $Security.Count
        OtherUpdatesWaiting    = $Other.Count
        DriverUpdatesWaiting   = $Drivers.Count
        UpdatesFailed          = $FailedOther.Count
        SecurityUpdatesFailed  = @($FailedOther | Where-Object { "$($_.class)" -in $SecurityClasses }).Count
        DriversFailed          = $FailedDrivers.Count
        LastSecurityUpdate     = $(if ($LastSecurity.Count -gt 0) { $LastSecurity[0].ToString('yyyy-MM-dd') } else { '' })
        UpdatesWaiting         = (@(@($Security) + @($Other) | ForEach-Object { "$($_.name)".Trim() }) -join '; ')
        DriversWaiting         = (@($Drivers | ForEach-Object { "$($_.name)".Trim() }) -join '; ')
        UpdatesFailing         = (@($FailedOther | ForEach-Object { "$($_.name)".Trim() }) -join '; ')
        DriversFailing         = (@($FailedDrivers | ForEach-Object { "$($_.name)".Trim() }) -join '; ')
    }
}
