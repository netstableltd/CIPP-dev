function Set-AteraMapping {
    <#
    .SYNOPSIS
        Replaces the CIPP tenant <-> Atera customer mappings with the table submitted from the
        Integrations > Atera > Tenant Mapping tab.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param (
        $CIPPMapping,
        $APIName,
        $Request
    )

    Get-CIPPAzDataTableEntity @CIPPMapping -Filter "PartitionKey eq 'AteraMapping'" | ForEach-Object {
        Remove-CIPPAzDataTableEntity -Force @CIPPMapping -Entity $_
    }

    $Count = 0
    foreach ($Mapping in @($Request.Body)) {
        if ([string]::IsNullOrWhiteSpace("$($Mapping.TenantId)") -or [string]::IsNullOrWhiteSpace("$($Mapping.IntegrationId)") -or "$($Mapping.IntegrationId)" -eq '-1') {
            continue
        }
        $AddObject = @{
            PartitionKey    = 'AteraMapping'
            RowKey          = "$($Mapping.TenantId)"
            IntegrationId   = "$($Mapping.IntegrationId)"
            IntegrationName = "$($Mapping.IntegrationName)"
        }
        Add-CIPPAzDataTableEntity @CIPPMapping -Entity $AddObject -Force
        $Count++
    }

    Write-LogMessage -API $APIName -headers $Request.Headers -message "Saved $Count Atera customer mapping(s)." -Sev 'Info'
    return [pscustomobject]@{ 'Results' = "Successfully saved $Count Atera mapping(s)." }
}
