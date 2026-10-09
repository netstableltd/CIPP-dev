function Get-AteraMapping {
    <#
    .SYNOPSIS
        Returns Atera customers and the current CIPP tenant <-> Atera customer mappings for the
        Integrations > Atera > Tenant Mapping tab.
    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $CIPPMapping
    )

    $ExtensionMappings = Get-ExtensionMapping -Extension 'Atera'
    $Tenants = Get-Tenants -IncludeErrors

    $Mappings = foreach ($Mapping in $ExtensionMappings) {
        $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey }
        if ($Tenant) {
            [PSCustomObject]@{
                TenantId        = $Tenant.customerId
                Tenant          = $Tenant.displayName
                TenantDomain    = $Tenant.defaultDomainName
                IntegrationId   = $Mapping.IntegrationId
                IntegrationName = $Mapping.IntegrationName
            }
        }
    }

    try {
        $AteraCustomers = Invoke-AteraRequest -Path 'customers' -All | Sort-Object CustomerName | ForEach-Object {
            [PSCustomObject]@{
                name  = $_.CustomerName
                value = "$($_.CustomerID)"
            }
        }
    } catch {
        $Message = if ($_.ErrorDetails.Message) { $_.ErrorDetails.Message } else { $_.Exception.Message }
        Write-LogMessage -Message "Could not get Atera customers: $Message" -sev 'Error' -tenant 'CIPP' -API 'AteraMapping'
        $AteraCustomers = @(@{ name = "Could not get Atera customers, error: $Message"; value = '-1' })
    }

    return [PSCustomObject]@{
        Companies = @($AteraCustomers)
        Mappings  = @($Mappings)
    }
}
