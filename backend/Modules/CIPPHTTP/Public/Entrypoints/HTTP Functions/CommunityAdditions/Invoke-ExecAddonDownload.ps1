function Invoke-ExecAddonDownload {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.Read
    .DESCRIPTION
        Community Additions > Settings > Add-ons: downloads an add-on package (.zip). Id gives an installed add-on's package (made when this CIPP image was built); RowKey gives an uploaded package. Returns application/zip.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $Id = "$($Request.Body.Id ?? $Request.Query.Id)"
    $RowKey = "$($Request.Body.RowKey ?? $Request.Query.RowKey)"
    $Fail = { param($Code, $Text) [HttpResponseContext]@{ StatusCode = $Code; Body = $Text } }

    if ($RowKey) {
        if ($RowKey -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]_\d+\.\d+\.\d+$') { return (& $Fail ([HttpStatusCode]::BadRequest) "That isn't an uploaded package.") }
        $Table = Get-CIPPTable -TableName 'AddonPackages'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Upload' and RowKey eq '$RowKey'" | Select-Object -First 1
        $Data = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UploadData' and RowKey eq '$RowKey'" | Select-Object -First 1
        if (-not $Row -or -not $Data.Package) { return (& $Fail ([HttpStatusCode]::NotFound) "That package isn't here any more.") }
        $Bytes = [Convert]::FromBase64String($Data.Package)
        $FileName = "$($Row.AddonId)-$($Row.Version).zip"
    } elseif ($Id) {
        $Manifest = if ($Id -match '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') { Get-CIPPAddonManifest -Id $Id } else { $null }
        if (-not $Manifest) { return (& $Fail ([HttpStatusCode]::NotFound) "There's no add-on '$Id' installed.") }
        $Package = Get-CIPPAddonInstalledPackage -Id $Id
        if (-not $Package) { return (& $Fail ([HttpStatusCode]::NotFound) "This CIPP wasn't built with a package for $($Manifest.name). Make one with build/tools/addons/Export-CippAddon.ps1.") }
        $Bytes = $Package.Bytes
        $FileName = "$Id-$($Manifest.version).zip"
    } else {
        return (& $Fail ([HttpStatusCode]::BadRequest) 'Give an add-on Id or an uploaded package RowKey.')
    }
    Write-LogMessage -headers $Request.Headers -API $Request.Params.CIPPEndpoint -message "Downloaded add-on package $FileName" -Sev Info
    [HttpResponseContext]@{
        StatusCode  = [HttpStatusCode]::OK
        ContentType = 'application/zip'
        Headers     = @{ 'Content-Disposition' = "attachment; filename=`"$FileName`"" }
        Body        = $Bytes
    }
}
