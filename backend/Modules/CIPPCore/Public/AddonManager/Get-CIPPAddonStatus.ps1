function Get-CIPPAddonStatus {
    <#
    .SYNOPSIS
        Everything the add-on manager shows: the installed add-ons with their compatibility and on/off
        state, and the uploaded packages.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$SkipLatest)

    $Running = Get-CIPPRunningVersion
    $Latest = if ($SkipLatest) { $null } else { Get-CIPPLatestCippVersion }
    $MajorMinor = { param($V) ((("$V" -split '[+\-\s]')[0]) -split '\.')[0..1] -join '.' }
    $Flags = @{}
    foreach ($F in @(Get-CIPPFeatureFlag | Where-Object { $_.Id -like 'Addon.*' })) { $Flags[$F.Id] = $F }

    $Installed = foreach ($M in @(Get-CIPPAddonManifest)) {
        $Compat = Test-CIPPAddonCompatibility -Manifest $M -CippVersion $Running
        $Flag = $Flags["Addon.$($M.id)"]
        $Package = Get-CIPPAddonInstalledPackage -Id $M.id
        [pscustomobject]@{
            Id                 = $M.id
            Name               = $M.name
            Version            = $M.version
            Description        = $M.description
            Author             = $M.author
            Category           = $M.category
            Enabled            = if ($Flag) { [bool]$Flag.Enabled } else { $true }
            Status             = $Compat.Status
            StatusMessage      = $Compat.Message
            MissingFunctions   = @($Compat.MissingFunctions)
            MissingEndpoints   = @($Compat.MissingEndpoints)
            MinVersion         = $M.cipp.minVersion
            TestedWith         = @($M.cipp.testedWith)
            TestedOnLatest     = if ($Latest) { [bool](@($M.cipp.testedWith) | Where-Object { (& $MajorMinor $_) -eq (& $MajorMinor $Latest) }) } else { $null }
            Menu               = @($M.menu)
            Endpoints          = @($M.endpoints)
            DependsOn          = [pscustomobject]@{ Functions = @($M.dependsOn.functions).Count; Frontend = @($M.dependsOn.frontend).Count }
            CoreChanges        = @($M.coreChanges)
            Storage            = @($M.storage)
            PackageAvailable   = [bool]$Package
            PackageSha256      = if ($Package) { $Package.Check.Sha256 } else { $null }
            PackageBytes       = if ($Package) { $Package.Check.Bytes } else { $null }
        }
    }

    $Table = Get-CIPPTable -TableName 'AddonPackages'
    $Uploads = foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Upload'")) {
        $Current = $Installed | Where-Object { $_.Id -eq $Row.AddonId } | Select-Object -First 1
        $Tested = @("$($Row.TestedWith)" -split ',' | Where-Object { $_ })
        $Compat = Test-CIPPAddonCompatibility -SkipRuntimeCheck -CippVersion $Running -Manifest ([pscustomobject]@{
                schema = 1; id = $Row.AddonId; name = $Row.Name; version = $Row.Version
                cipp = [pscustomobject]@{ minVersion = $Row.MinVersion; testedWith = $Tested }
            })
        [pscustomobject]@{
            RowKey        = $Row.RowKey
            Id            = $Row.AddonId
            Name          = $Row.Name
            Version       = $Row.Version
            FileName      = $Row.FileName
            Bytes         = [int64]$Row.Bytes
            Sha256        = $Row.Sha256
            UploadedBy    = $Row.UploadedBy
            UploadedAt    = $Row.UploadedAt
            Warnings      = @("$($Row.Warnings)" | Where-Object { $_ } | ForEach-Object { try { $_ | ConvertFrom-Json } catch { } })
            Status        = $Compat.Status
            StatusMessage = $Compat.Message
            TestedWith    = $Tested
            Installed     = if (-not $Current) { 'New' } else {
                switch (Compare-CIPPVersion $Row.Version $Current.Version) { 1 { 'Upgrade' } 0 { 'Installed' } -1 { 'Older' } }
            }
            InstalledVersion = $Current.Version
        }
    }

    [pscustomobject]@{
        CippVersion       = $Running
        LatestCippVersion = $Latest
        Addons            = @($Installed)
        Uploads           = @($Uploads | Sort-Object UploadedAt -Descending)
        Limits            = (Get-CIPPAddonLayout).limits
    }
}
