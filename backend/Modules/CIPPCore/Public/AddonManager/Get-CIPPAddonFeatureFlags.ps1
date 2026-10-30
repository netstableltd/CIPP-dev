function Get-CIPPAddonFeatureFlags {
    <#
    .SYNOPSIS
        One feature flag per installed add-on (Id Addon.<id>), so CIPP's feature flags turn add-ons on and off.

    .DESCRIPTION
        Get-CIPPFeatureFlag and Set-CIPPFeatureFlag add these to the flags in FeatureFlags.json. A turned-off
        add-on's endpoints are refused by the HTTP router and its menu entries hidden, exactly like any other
        flag. The flags are Hidden from CIPP > Settings > Features: add-ons are turned on and off in
        Community Additions > Settings > Add-ons.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$Refresh)

    # Called on every HTTP request (through Get-CIPPFeatureFlag), and the manifests are part of the
    # image, so they are read once per worker.
    if ($script:CIPPAddonFeatureFlags -and -not $Refresh) { return $script:CIPPAddonFeatureFlags }
    $script:CIPPAddonFeatureFlags = @(foreach ($M in @(Get-CIPPAddonManifest)) {
        if (-not $M.id) { continue }
        [pscustomobject]@{
            Id              = "Addon.$($M.id)"
            Name            = "Add-on: $($M.name)"
            Description     = "$($M.description)"
            Enabled         = $true
            AllowUserToggle = $true
            Timers          = @()
            Endpoints       = @($M.endpoints | Where-Object { $_ })
            Pages           = @($M.menu | Where-Object { $_.path } | ForEach-Object { $_.path })
            Hidden          = $true
        }
    })
    $script:CIPPAddonFeatureFlags
}
