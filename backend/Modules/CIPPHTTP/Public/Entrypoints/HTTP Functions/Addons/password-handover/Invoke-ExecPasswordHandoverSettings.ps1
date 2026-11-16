function Invoke-ExecPasswordHandoverSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Community Additions > Password hand-over (add-on password-handover): saves the add-on's settings (Settings: expireAfterDays 1-90, expireAfterViews 1-100, passphrase email or none, retrievalStep, mustChange, signInUrl, subject, message with {link}), or with Reset true goes back to the defaults. Stored in table AddonSettings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Table = Get-CIPPTable -TableName 'AddonSettings'
    try {
        if ($Request.Body.Reset -eq $true) {
            $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'password-handover' and RowKey eq 'settings'" | Select-Object -First 1
            if ($Row) { Remove-CIPPAzDataTableEntity @Table -Entity $Row -Force | Out-Null }
            Write-LogMessage -headers $Request.Headers -API $APIName -message 'Password hand-over settings set back to the defaults.' -Sev 'Info'
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = 'Back to the default settings.' } })
        }
        try { $Clean = Test-CIPPPasswordHandoverSettings -Settings $Request.Body.Settings } catch {
            return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = $_.Exception.Message } })
        }
        Add-CIPPAzDataTableEntity @Table -Entity @{ PartitionKey = 'password-handover'; RowKey = 'settings'; Settings = [string]($Clean | ConvertTo-Json -Compress) } -Force
        Write-LogMessage -headers $Request.Headers -API $APIName -message "Saved the password hand-over settings ($($Clean.expireAfterDays) days, $($Clean.expireAfterViews) views, passphrase $($Clean.passphrase))." -Sev 'Info'
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = 'Settings saved.' } })
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::InternalServerError; Body = @{ Results = "The settings weren't saved: $($ErrorMessage.NormalizedError)" } })
    }
}
