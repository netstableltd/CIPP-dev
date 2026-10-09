function Invoke-AteraAutoMap {
    <#
    .SYNOPSIS
        Automatically maps unmapped CIPP tenants to Atera customers.

    .DESCRIPTION
        Atera customers carry a Domain field, which is a far more reliable match than names
        (trading names and legal names often differ). For each tenant that has no mapping yet:

          1. Domain match: the tenant's default or initial (.onmicrosoft.com) domain equals one of
             the Atera customer's domains (the Domain field may hold several, separated by
             commas, semicolons or spaces).
          2. Name match: normalised display name equals normalised Atera customer name
             (lower-case, punctuation removed, trailing legal suffixes such as Ltd/Limited removed).

        A match is only used when exactly one Atera customer qualifies. Existing mappings are never
        changed, and each Atera customer is used at most once by auto-mapping. Matches should still
        be reviewed - a domain recorded against the wrong Atera customer will map the wrong way.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        $CIPPMapping,
        $APIName = 'AteraAutoMap',
        $Headers
    )

    function ConvertTo-NormalisedName([string]$Name) {
        $n = ($Name ?? '').ToLowerInvariant() -replace "[.,'()&\-/]", ' ' -replace '\s+', ' '
        $n = $n.Trim()
        while ($n -match '\s(ltd|limited|llc|llp|inc|incorporated|plc|pty|corp|corporation|gmbh|bv|co|group)$') {
            $n = ($n -replace '\s(ltd|limited|llc|llp|inc|incorporated|plc|pty|corp|corporation|gmbh|bv|co|group)$', '').Trim()
        }
        $n = $n -replace '^the\s', ''
        return $n
    }

    $Existing = @(Get-ExtensionMapping -Extension 'Atera')
    $MappedTenantIds = @($Existing.RowKey)
    $UsedCustomerIds = [System.Collections.Generic.HashSet[string]]::new([string[]]@($Existing.IntegrationId | Where-Object { $_ }))

    $Tenants = Get-Tenants -IncludeErrors | Where-Object { $_.customerId -notin $MappedTenantIds }
    $Customers = @(Invoke-AteraRequest -Path 'customers' -All)

    $ByDomain = @{}
    foreach ($Customer in $Customers) {
        foreach ($Domain in (("$($Customer.Domain)" -split '[,;\s]+') | Where-Object { $_ })) {
            $Key = $Domain.ToLowerInvariant().Trim()
            if (-not $ByDomain.ContainsKey($Key)) { $ByDomain[$Key] = [System.Collections.Generic.List[object]]::new() }
            $ByDomain[$Key].Add($Customer)
        }
    }

    $Added = [System.Collections.Generic.List[string]]::new()
    $Skipped = [System.Collections.Generic.List[string]]::new()

    foreach ($Tenant in $Tenants) {
        $Candidates = @()
        $Method = $null
        foreach ($Domain in @($Tenant.defaultDomainName, $Tenant.initialDomainName) | Where-Object { $_ }) {
            $Key = $Domain.ToLowerInvariant()
            if ($ByDomain.ContainsKey($Key)) { $Candidates += $ByDomain[$Key] }
        }
        $Candidates = @($Candidates | Sort-Object CustomerID -Unique | Where-Object { -not $UsedCustomerIds.Contains("$($_.CustomerID)") })
        if ($Candidates.Count -ge 1) { $Method = 'domain' }

        if ($Candidates.Count -eq 0) {
            $TenantName = ConvertTo-NormalisedName $Tenant.displayName
            if ($TenantName) {
                $Candidates = @($Customers | Where-Object {
                        (ConvertTo-NormalisedName $_.CustomerName) -eq $TenantName -and -not $UsedCustomerIds.Contains("$($_.CustomerID)")
                    })
                if ($Candidates.Count -ge 1) { $Method = 'name' }
            }
        }

        if ($Candidates.Count -eq 1) {
            $Match = $Candidates[0]
            $Entity = @{
                PartitionKey    = 'AteraMapping'
                RowKey          = "$($Tenant.customerId)"
                IntegrationId   = "$($Match.CustomerID)"
                IntegrationName = "$($Match.CustomerName)"
            }
            Add-CIPPAzDataTableEntity @CIPPMapping -Entity $Entity -Force
            $null = $UsedCustomerIds.Add("$($Match.CustomerID)")
            $Added.Add("$($Tenant.displayName) -> $($Match.CustomerName) ($Method)")
        } elseif ($Candidates.Count -gt 1) {
            $Skipped.Add("$($Tenant.displayName) (matches $($Candidates.Count) Atera customers)")
        }
    }

    $Message = "Atera auto-mapping: mapped $($Added.Count) tenant(s)"
    if ($Skipped.Count -gt 0) { $Message += ", skipped $($Skipped.Count) ambiguous" }
    $Message += '. Review the matches - names that differ a lot are worth a second look.'
    Write-LogMessage -API $APIName -headers $Headers -tenant 'Global' -message $Message -Sev 'Info' -LogData @{ Added = @($Added); Skipped = @($Skipped) }

    return $Message
}
