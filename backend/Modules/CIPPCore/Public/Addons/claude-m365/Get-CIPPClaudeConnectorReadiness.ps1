function Get-CIPPClaudeConnectorReadiness {
    <#
    .SYNOPSIS
        What a tenant already has that we recommend before giving Claude access to Microsoft 365: a
        third-party backup, Entra ID P1, Microsoft Defender and Microsoft 365 Business Premium.

    .DESCRIPTION
        Used for the customer information PDF and the information box on the Claude for Microsoft 365
        standard process.

        Backup        Enterprise apps from known Microsoft 365 backup products. Barracuda Cloud-to-Cloud Backup
                      is recognised by its app ID (its enterprise app is called just 'Cloud-to-Cloud-Backup');
                      others by publisher or name together with a backup word, and are listed if found.
                      'Barracuda M365 Link' and 'BarracudaONE' are Barracuda's portal and email links, not
                      backup.
        EntraP1       An enabled licence with the AAD_PREMIUM or AAD_PREMIUM_P2 service plan.
        Defender      Enabled licences with a Defender for Business / Endpoint / Office 365 service plan.
        Suite         Microsoft 365 Business Premium, E5 or E3, if the tenant has one.

        Each check is independent; one that can't be read is $null rather than failing the rest.

    .PARAMETER Skus
        subscribedSkus already read by the caller (saves a Graph call).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        $Skus
    )

    $DefenderPlans = [ordered]@{
        MDE_SMB             = 'Microsoft Defender for Business'
        MDE_LITE            = 'Microsoft Defender for Endpoint P1'
        WINDEFATP           = 'Microsoft Defender for Endpoint P2'
        ATP_ENTERPRISE      = 'Microsoft Defender for Office 365 (Plan 1)'
        THREAT_INTELLIGENCE = 'Microsoft Defender for Office 365 (Plan 2)'
    }
    $BackupVendors = '(?i)\b(barracuda|datto|backupify|veeam|avepoint|acronis|dropsuite|spanning|skykick|keepit|redstor|cloudally|commvault|metallic|druva|axcient|unitrends|cove data protection|n-able|msp360|synology|kaseya 365|arcserve|afi\.ai)\b'
    $BackupWords = '(?i)backup|back-up|cloud.?to.?cloud|saas protection|data protection|recovery'
    # Known backup apps by app ID: name shown, and whether it is Barracuda's.
    $KnownBackupApps = @{
        '09e6e8ef-2c94-4106-89dd-d0a7e500a886' = @{ Name = 'Barracuda Cloud-to-Cloud Backup'; Barracuda = $true }
    }
    $BarracudaOwner = 'b893e0b8-2743-4fa7-81eb-0155a9060350'
    $MicrosoftOwners = @('f8cdef31-a31e-4b4a-93e4-5f571e91255a', '72f988bf-86f1-41af-91ab-2d7cd011db47', '33e01921-4d64-4f8c-a055-5bdaffd5e33d', 'cdc5aeea-15c5-4db6-b079-fcadd2505dc2')

    # --- Licences ------------------------------------------------------------------------------------------
    $EntraP1 = $null; $Defender = $null; $Suite = $null
    try {
        if ($null -eq $Skus) { $Skus = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/subscribedSkus?$select=skuPartNumber,capabilityStatus,servicePlans,prepaidUnits' -tenantid $TenantFilter) }
        # Every tenant has at least one subscription; none back means the read didn't reach the tenant.
        if (@($Skus | Where-Object { $_.skuPartNumber }).Count -eq 0) { throw 'No subscriptions returned' }
        $Active = @($Skus | Where-Object { $_.capabilityStatus -eq 'Enabled' })
        $Plans = @($Active | ForEach-Object { $_.servicePlans } | Where-Object { $_.provisioningStatus -ne 'Disabled' } | ForEach-Object { "$($_.servicePlanName)" })
        $EntraP1 = [bool]($Plans | Where-Object { $_ -in @('AAD_PREMIUM', 'AAD_PREMIUM_P2') })
        $Found = @($DefenderPlans.Keys | Where-Object { $Plans -contains $_ } | ForEach-Object { $DefenderPlans[$_] })
        $Defender = [pscustomobject]@{ Found = ($Found.Count -gt 0); Products = $Found }
        $Parts = @($Active | ForEach-Object { "$($_.skuPartNumber)" })
        $Suite = if ($Parts | Where-Object { $_ -match '^SPB' -or $_ -match '(?i)^Microsoft_365_Business_Premium' }) { 'Microsoft 365 Business Premium' }
        elseif ($Parts | Where-Object { $_ -match '(?i)^(SPE_E5|Microsoft_365_E5)' }) { 'Microsoft 365 E5' }
        elseif ($Parts | Where-Object { $_ -match '(?i)^(SPE_E3|Microsoft_365_E3)' }) { 'Microsoft 365 E3' }
        else { $null }
    } catch { Write-Verbose "Couldn't read licences: $($_.Exception.Message)" }

    # --- Backup --------------------------------------------------------------------------------------------
    $Backup = $null
    try {
        $Sps = @(New-GraphGetRequest -uri 'https://graph.microsoft.com/v1.0/servicePrincipals?$select=displayName,appId,appOwnerOrganizationId,publisherName,accountEnabled&$top=999' -tenantid $TenantFilter)
        # Every tenant has Microsoft's own enterprise apps; none back means the read didn't reach the tenant.
        if (@($Sps | Where-Object { $_.displayName }).Count -eq 0) { throw 'No enterprise apps returned' }
        $Matched = @($Sps | Where-Object { $_.accountEnabled -ne $false -and "$($_.appOwnerOrganizationId)" -notin $MicrosoftOwners } | ForEach-Object {
                $Sp = $_
                $Known = $KnownBackupApps["$($Sp.appId)"]
                $Vendor = "$($Sp.displayName) $($Sp.publisherName)" -match $BackupVendors
                if ($Known) {
                    [pscustomobject]@{ Name = $Known.Name; Barracuda = [bool]$Known.Barracuda }
                } elseif ($Vendor -and "$($Sp.displayName)" -match $BackupWords) {
                    $IsBarracuda = "$($Sp.appOwnerOrganizationId)" -eq $BarracudaOwner -or "$($Sp.displayName) $($Sp.publisherName)" -match '(?i)barracuda'
                    $Name = if ($IsBarracuda -and "$($Sp.displayName)" -notmatch '(?i)barracuda') { "Barracuda $($Sp.displayName)" } else { "$($Sp.displayName)" }
                    [pscustomobject]@{ Name = $Name; Barracuda = [bool]$IsBarracuda }
                }
            })
        $Apps = @($Matched | ForEach-Object { $_.Name } | Sort-Object -Unique)
        $Backup = [pscustomobject]@{
            Found     = ($Apps.Count -gt 0)
            Barracuda = [bool]($Matched | Where-Object { $_.Barracuda })
            Products  = $Apps
        }
    } catch { Write-Verbose "Couldn't read enterprise apps: $($_.Exception.Message)" }

    [pscustomobject]@{
        Backup          = $Backup
        EntraP1         = $EntraP1
        Defender        = $Defender
        Suite           = $Suite
        BusinessPremium = ($Suite -eq 'Microsoft 365 Business Premium')
    }
}
