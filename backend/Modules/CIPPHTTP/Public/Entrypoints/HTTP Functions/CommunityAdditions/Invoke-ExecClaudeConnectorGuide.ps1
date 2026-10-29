function Invoke-ExecClaudeConnectorGuide {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Community Additions > Standard Processes > Claude for Microsoft 365: the connection guide added to the end of the setup summary PDF. Action Upload saves a Word document (FileName, Data as base64 or a data URL; .docx, up to 10 MB), checking first that it can be read; Action Remove deletes it. The guide is kept in this CIPP instance, not in the code.
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

    $Table = Get-CIPPTable -TableName 'CommunityProcesses'
    $Action = "$($Body.Action)"

    if ($Action -eq 'Remove') {
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ClaudeM365' and RowKey eq 'Guide'" | Select-Object -First 1
        if ($Row) { Remove-CIPPAzDataTableEntity @Table -Entity $Row -Force | Out-Null }
        Write-LogMessage -headers $Headers -API $APIName -message 'Removed the Claude connection guide' -Sev Info
        return (& $Respond ([HttpStatusCode]::OK) 'Removed the connection guide.' $null)
    }
    if ($Action -ne 'Upload') { return (& $Respond ([HttpStatusCode]::BadRequest) 'Action must be Upload or Remove.' $null) }

    # Just the name: browsers can send a path ("C:\fakepath\guide.docx").
    $FileName = @("$($Body.FileName)" -split '[\\/]')[-1].Trim()
    if ($FileName -notmatch '(?i)\.docx$' -or $FileName.Length -gt 200) { return (& $Respond ([HttpStatusCode]::BadRequest) 'Choose a Word document (.docx).' $null) }
    $Data = "$($Body.Data)" -replace '^data:[^;]*;base64,', ''
    try { $Bytes = [Convert]::FromBase64String($Data) } catch { return (& $Respond ([HttpStatusCode]::BadRequest) "The file couldn't be read." $null) }
    if ($Bytes.Length -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'The file is empty.' $null) }
    if ($Bytes.Length -gt 10MB) { return (& $Respond ([HttpStatusCode]::BadRequest) 'The guide must be 10 MB or smaller.' $null) }

    try {
        $Converted = ConvertFrom-CIPPDocxGuide -Bytes $Bytes
    } catch {
        return (& $Respond ([HttpStatusCode]::BadRequest) "That document couldn't be read: $($_.Exception.Message)" $null)
    }
    if (@($Converted.Blocks).Count -eq 0) { return (& $Respond ([HttpStatusCode]::BadRequest) 'That document has no content to add.' $null) }

    $Entity = @{
        PartitionKey = 'ClaudeM365'
        RowKey       = 'Guide'
        Docx         = [Convert]::ToBase64String($Bytes)
        FileName     = $FileName
        Title        = "$($Converted.Title)"
        Images       = "$($Converted.Images)"
        UploadedBy   = "$User"
        UploadedAt   = (Get-Date).ToUniversalTime().ToString('o')
    }
    try {
        Add-CIPPAzDataTableEntity @Table -Entity $Entity -Force | Out-Null
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return (& $Respond ([HttpStatusCode]::InternalServerError) "Couldn't save the guide: $($ErrorMessage.NormalizedError)" $null)
    }
    Write-LogMessage -headers $Headers -API $APIName -message "Saved the Claude connection guide '$FileName'" -Sev Info
    $Guide = [pscustomobject]@{ FileName = $FileName; Title = $Entity.Title; Images = [int]$Converted.Images; UploadedBy = "$User"; UploadedAt = $Entity.UploadedAt }
    & $Respond ([HttpStatusCode]::OK) "Saved '$FileName': $($Converted.Title), $($Converted.Images) picture$(if ($Converted.Images -ne 1) { 's' })." $Guide
}
