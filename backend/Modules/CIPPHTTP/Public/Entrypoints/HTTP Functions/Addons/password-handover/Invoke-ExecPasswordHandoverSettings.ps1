function Invoke-ExecPasswordHandoverSettings {
    <#
    .FUNCTIONALITY
        Entrypoint
    .ROLE
        CIPP.AppSettings.ReadWrite
    .DESCRIPTION
        Community Additions > Password hand-over (add-on password-handover): saves the add-on's settings (Settings: serverUrl, blank for the integration's server; expireAfterDays 1-90, expireAfterViews 1-100, passphrase email or none, retrievalStep, mustChange, signInUrl, subject, message with {link}), with Reset true goes back to the defaults, or with Test true makes a throwaway link (1 view, 1 day) on Settings.serverUrl (or the integration's server) to check it works. Stored in table AddonSettings.
    #>
    [CmdletBinding()]
    param($Request, $TriggerMetadata)

    $APIName = $Request.Params.CIPPEndpoint
    $Table = Get-CIPPTable -TableName 'AddonSettings'
    try {
        if ($Request.Body.Test -eq $true) {
            # A throwaway push (1 day, 1 view) to the address on the page, saved or not.
            $Address = "$($Request.Body.Settings.serverUrl)".Trim().TrimEnd('/')
            if ($Address -and $Address -notmatch '^https://[A-Za-z0-9.-]+(:\d+)?(/[^\s<>"]*)?$') {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = 'The Password Pusher address must start with https://.' } })
            }
            try {
                $Connection = Get-CIPPPasswordHandoverConnection -ServerUrl $Address
                $Link = (New-CIPPPwPush -Connection $Connection -Payload 'This is a test link from CIPP. If you can read this, password hand-over works.' -ExpireAfterDays 1 -ExpireAfterViews 1 -RetrievalStep $true -DeletableByViewer $true).Link
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::OK; Body = @{ Results = "It works: $($Connection.BaseUrl) made a test link (1 view, 1 day): $Link" } })
            } catch {
                return ([HttpResponseContext]@{ StatusCode = [HttpStatusCode]::BadRequest; Body = @{ Results = "The test link couldn't be made: $($_.Exception.Message)" } })
            }
        }
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
