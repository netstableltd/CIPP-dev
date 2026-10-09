function Start-ExtensionOrchestrator {
    <#
    .SYNOPSIS
        Start the Extension Orchestrator
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding(SupportsShouldProcess = $true)]
    param()

    $Table = Get-CIPPTable -TableName Extensionsconfig
    $ExtensionConfig = (Get-AzDataTableEntity @Table).config
    if ($ExtensionConfig -and (Test-Json -Json $ExtensionConfig)) {
        $Configuration = ($ExtensionConfig | ConvertFrom-Json)
    } else {
        $Configuration = @{}
    }

    Write-Host 'Started Scheduler for Extensions'

    # NinjaOne Extension
    if ($Configuration.NinjaOne.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('Invoke-NinjaOneExtensionScheduler')) {
            Invoke-NinjaOneExtensionScheduler
        }
    }

    # Atera Extension (nightly account-wide sync into the Reporting DB)
    if ($Configuration.Atera.Enabled -eq $true) {
        if ($PSCmdlet.ShouldProcess('Invoke-AteraExtensionScheduler')) {
            try {
                Invoke-AteraExtensionScheduler
            } catch {
                Write-LogMessage -API 'AteraSync' -tenant 'Global' -message "Could not queue Atera sync: $($_.Exception.Message)" -Sev 'Error'
            }
        }
    }
}
