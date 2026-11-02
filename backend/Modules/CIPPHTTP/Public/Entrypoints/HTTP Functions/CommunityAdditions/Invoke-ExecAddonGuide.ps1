function Invoke-ExecAddonGuide {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Community Additions: a how-to guide for an add-on (AddonId), one of the guides its addon.json lists (Key). Action Upload saves a Word document (FileName, Data as base64 or a data URL; .docx, up to 10 MB), checking first that it can be read; Action Remove deletes it. Guides are kept in this CIPP instance, not in the code, and added to the end of the add-on's PDFs.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body
    $Respond = { param($Code, $Text, $Guide) [HttpResponseContext]@{ StatusCode = $Code; Body = @{ Results = $Text; Guide = $Guide } } }
    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }

    $AddonId = "$($Body.AddonId)"
    $Key = "$($Body.Key)"
    $Manifest = if ($AddonId -match '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') { Get-CIPPAddonManifest -Id $AddonId } else { $null }
    if (-not $Manifest) { return (& $Respond ([HttpStatusCode]::NotFound) "There's no add-on '$AddonId' installed." $null) }
    $Declared = @($Manifest.guides | Where-Object { $_.key -eq $Key }) | Select-Object -First 1
    if (-not $Declared) { return (& $Respond ([HttpStatusCode]::BadRequest) "$($Manifest.name) has no guide '$Key'." $null) }

    $Table = Get-CIPPTable -TableName 'AddonGuides'
    $Action = "$($Body.Action)"
    if ($Action -eq 'Remove') {
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$AddonId' and RowKey eq '$Key'" | Select-Object -First 1
        if ($Row) { Remove-CIPPAzDataTableEntity @Table -Entity $Row -Force | Out-Null }
        Write-LogMessage -headers $Headers -API $APIName -message "Removed the $($Declared.title) guide for $($Manifest.name)" -Sev Info
        return (& $Respond ([HttpStatusCode]::OK) 'Removed the guide.' $null)
    }
    if ($Action -ne 'Upload') { return (& $Respond ([HttpStatusCode]::BadRequest) 'Action must be Upload or Remove.' $null) }

    $FileName = @("$($Body.FileName)" -split '[\\/]')[-1].Trim()
    if ($FileName -notmatch '(?i)\.docx$' -or $FileName.Length -gt 200) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose a Word document (.docx).' $null) }
    $Data = "$($Body.Data)" -replace '^data:[^;]*;base64,', ''
    try { $Bytes = [Convert]::FromBase64String($Data) } catch { return (& $Respond ([HttpStatusCode]::BadRequest) "The file couldn't be read." $null) }
    if ($Bytes.Length -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'The file is empty.' $null) }
    if ($Bytes.Length -gt 10MB) { return (& $Respond ([HttpStatusCode]::BadRequest) 'The guide must be 10 MB or smaller.' $null) }
    try { $Converted = ConvertFrom-CIPPDocxGuide -Bytes $Bytes }
    catch { return (& $Respond ([HttpStatusCode]::BadRequest) "That document couldn't be read: $($_.Exception.Message)" $null) }
    if (@($Converted.Blocks).Count -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'That document has no content to add.' $null) }

    $Entity = @{
        PartitionKey = $AddonId
        RowKey       = $Key
        Docx         = [Convert]::ToBase64String($Bytes)
        FileName     = $FileName
        Title        = "$($Converted.Title)"
        Images       = "$($Converted.Images)"
        UploadedBy   = "$User"
        UploadedAt   = (Get-Date).ToUniversalTime().ToString('o')
    }
    try { Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null }
    catch { return (& $Respond ([HttpStatusCode]::InternalServerError) "Couldn't save the guide: $((Get-CippException -Exception $_).NormalizedError)" $null) }
    Write-LogMessage -headers $Headers -API $APIName -message "Saved the $($Declared.title) guide for $($Manifest.name): '$FileName'" -Sev Info
    $Guide = [pscustomobject]@{ AddonId = $AddonId; Key = $Key; FileName = $FileName; Title = $Entity.Title; Images = [int]$Converted.Images; UploadedBy = "$User"; UploadedAt = $Entity.UploadedAt }
    & $Respond ([HttpStatusCode]::OK) "Saved '$FileName': $($Converted.Title), $($Converted.Images) picture$(if ($Converted.Images -ne 1) { 's' })." $Guide
}
