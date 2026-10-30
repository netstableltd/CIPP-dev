function Invoke-ExecAddon {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Community Additions > Settings > Add-ons. Action Enable or Disable (Id) turns an installed add-on on or off: a turned-off add-on's pages leave the menu and its API endpoints are refused. Action Upload (FileName, Data as base64 or a data URL) checks an add-on package (.zip) and keeps it in this instance so it can be downloaded and installed into the repository; nothing in it is run. Action DeleteUpload (RowKey) removes an uploaded package.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Headers = $Request.Headers
    $Body = $Request.Body
    $Respond = { param($Code, $Results, $Extra) $B = @{ Results = $Results }; if ($Extra) { foreach ($K in $Extra.Keys) { $B[$K] = $Extra[$K] } }; [HttpResponseContext]@{ StatusCode = $Code; Body = $B } }
    try {
        $User = ([System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($Headers.'x-ms-client-principal')) | ConvertFrom-Json).userDetails
    } catch { $User = 'Unknown' }
    $Action = "$($Body.Action)"

    try {
        switch ($Action) {
            { $_ -in 'Enable', 'Disable' } {
                $Id = "$($Body.Id)"
                $Manifest = if ($Id -match '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$') { Get-CIPPAddonManifest -Id $Id } else { $null }
                if (-not $Manifest) { return (& $Respond ([HttpStatusCode]::NotFound) "There's no add-on '$Id' installed.") }
                $Enabled = $Action -eq 'Enable'
                if (-not (Set-CIPPFeatureFlag -Id "Addon.$Id" -Enabled $Enabled)) { return (& $Respond ([HttpStatusCode]::InternalServerError) "Couldn't turn $($Manifest.name) $(if ($Enabled) { 'on' } else { 'off' }).") }
                Write-LogMessage -headers $Headers -API $APIName -message "Turned the add-on $($Manifest.name) ($Id) $(if ($Enabled) { 'on' } else { 'off' })" -Sev Info
                return (& $Respond ([HttpStatusCode]::OK) "$($Manifest.name) is turned $(if ($Enabled) { 'on' } else { 'off' }).")
            }
            'Upload' {
                $Layout = Get-CIPPAddonLayout
                $FileName = @("$($Body.FileName)" -split '[\\/]')[-1].Trim()
                if ($FileName -notmatch '(?i)\.zip$' -or $FileName.Length -gt 200) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose an add-on package (.zip).') }
                $Data = "$($Body.Data)" -replace '^data:[^;]*;base64,', ''
                try { $Bytes = [Convert]::FromBase64String($Data) } catch { return (& $Respond ([HttpStatusCode]::BadRequest) "The file couldn't be read.") }
                if ($Bytes.Length -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'The file is empty.') }

                $Check = Test-CIPPAddonPackage -Bytes $Bytes -Layout $Layout
                $Errors = [System.Collections.Generic.List[string]]::new()
                foreach ($E in $Check.Errors) { $Errors.Add($E) }
                if ($Check.Valid) {
                    # Names already used by CIPP. An installed add-on of the same id may reuse its own names
                    # (an upgrade), so its package's names don't count as clashes.
                    $Installed = Get-CIPPAddonInstalledPackage -Id $Check.Manifest.id
                    $Own = @($Installed.Check.Files | Where-Object { $_.Area -in 'backend/functions', 'backend/endpoints' } | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Path) })
                    $SameIdInstalled = [bool](Get-CIPPAddonManifest -Id $Check.Manifest.id)
                    foreach ($F in @($Check.Files | Where-Object { $_.Area -in 'backend/functions', 'backend/endpoints' })) {
                        $Name = [System.IO.Path]::GetFileNameWithoutExtension($F.Path)
                        if ($Own -contains $Name -or ($SameIdInstalled -and -not $Installed)) { continue }
                        if (Get-Command -Name $Name -ErrorAction SilentlyContinue) { $Errors.Add("$Name is already a CIPP function; the add-on's would clash with it.") }
                    }
                }
                if ($Errors.Count -gt 0) {
                    Write-LogMessage -headers $Headers -API $APIName -message "Refused add-on package '$FileName': $($Errors -join ' ')" -Sev Warning
                    return (& $Respond ([HttpStatusCode]::BadRequest) "That package can't be used: $($Errors.Count) problem$(if ($Errors.Count -ne 1) { 's' })." @{ Errors = @($Errors); Warnings = @($Check.Warnings) })
                }

                $M = $Check.Manifest
                $Table = Get-CIPPTable -TableName 'AddonPackages'
                $RowKey = "$($M.id)_$($M.version)"
                $Entity = @{
                    PartitionKey = 'Upload'
                    RowKey       = $RowKey
                    AddonId      = "$($M.id)"
                    Name         = "$($M.name)"
                    Version      = "$($M.version)"
                    MinVersion   = "$($M.cipp.minVersion)"
                    TestedWith   = (@($M.cipp.testedWith) -join ',')
                    FileName     = $FileName
                    Bytes        = [int64]$Check.Bytes
                    Sha256       = $Check.Sha256
                    Warnings     = (ConvertTo-Json -InputObject @($Check.Warnings) -Compress)
                    UploadedBy   = "$User"
                    UploadedAt   = (Get-Date).ToUniversalTime().ToString('o')
                }
                # The package itself goes in its own partition: it can be split over several rows for
                # size, and the list only reads the small 'Upload' rows.
                Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'UploadData'; RowKey = $RowKey; Package = [Convert]::ToBase64String($Bytes) } -Force | Out-Null
                Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
                Write-LogMessage -headers $Headers -API $APIName -message "Uploaded add-on package $($M.name) $($M.version) ($FileName, sha256 $($Check.Sha256))" -Sev Info
                return (& $Respond ([HttpStatusCode]::OK) "Checked and saved $($M.name) $($M.version)." @{ Warnings = @($Check.Warnings); RowKey = $RowKey })
            }
            'DeleteUpload' {
                $RowKey = "$($Body.RowKey)"
                if ($RowKey -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]_\d+\.\d+\.\d+$') { return (& $Respond ([HttpStatusCode]::BadRequest) "That isn't an uploaded package.") }
                $Table = Get-CIPPTable -TableName 'AddonPackages'
                $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Upload' and RowKey eq '$RowKey'")
                if ($Rows.Count -eq 0) { return (& $Respond ([HttpStatusCode]::NotFound) "That package isn't here any more.") }
                Remove-CIPPAzDataTableEntity @Table -Entity $Rows[0] -Force | Out-Null
                $Data = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'UploadData' and RowKey eq '$RowKey'" | Select-Object -First 1
                if ($Data) { Remove-CIPPAzDataTableEntity @Table -Entity $Data -Force | Out-Null }
                Write-LogMessage -headers $Headers -API $APIName -message "Removed the uploaded add-on package $RowKey" -Sev Info
                return (& $Respond ([HttpStatusCode]::OK) "Removed $($Rows[0].Name) $($Rows[0].Version).")
            }
            default { return (& $Respond ([HttpStatusCode]::BadRequest) 'Action must be Enable, Disable, Upload or DeleteUpload.') }
        }
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -headers $Headers -API $APIName -message "Add-on $Action failed: $($ErrorMessage.NormalizedError)" -Sev Error -LogData $ErrorMessage
        return (& $Respond ([HttpStatusCode]::InternalServerError) "That didn't work: $($ErrorMessage.NormalizedError)")
    }
}
