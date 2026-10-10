function Get-CIPPReportBreachData {
    <#
    .SYNOPSIS
        Finds the tenant's email addresses that appear in known data breaches, for the monthly report.

    .DESCRIPTION
        Uses CIPP's own breach lookup (Get-BreachInfo: CyberDrain's breach service, searched by every
        domain in the tenant - no Have I Been Pwned API key or domain verification needed). When the
        live lookup fails, falls back to the results CIPP already cached in the UserBreaches table (the
        Breach alert and Tools > Tenant Breach Lookup fill it).

        Breach names are matched against Have I Been Pwned's public breach catalogue
        (https://haveibeenpwned.com/api/v3/breaches - no key needed) for the breach title, date and what
        was exposed. Names not in the catalogue are kept as given.

        Passwords or password hashes in the source data are never read into the output.

    .PARAMETER TenantFilter
        Tenant default domain.

    .PARAMETER Users
        Optional Reporting DB Users rows, to mark which addresses belong to current accounts.

    .OUTPUTS
        @{ Source = 'Live'|'Cache'|'None'; CheckedAt; Error; Accounts = @(@{ email; current; breaches = @(@{ name; title; date; classes }) });
           Total; Current; WithPasswords }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [object[]]$Users = @()
    )

    $Result = @{ Source = 'None'; CheckedAt = (Get-Date).ToUniversalTime(); Error = $null; Accounts = @(); Total = 0; Current = 0; WithPasswords = 0 }

    # Raw records: email + sources (breach names). Only those two fields are kept.
    $Records = $null
    try {
        $Records = @(Get-BreachInfo -TenantFilter $TenantFilter | ForEach-Object { $_ } | Where-Object { $_ -and $_.email } | ForEach-Object { @{ email = "$($_.email)"; sources = $_.sources } })
        $Result.Source = 'Live'
    } catch {
        $Result.Error = $_.Exception.Message
        try {
            $Table = Get-CIPPTable -TableName 'UserBreaches'
            $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$TenantFilter'")
            if ($Rows.Count -gt 0) {
                $Records = @(foreach ($Row in $Rows) { @($Row.breaches | ConvertFrom-Json -ErrorAction SilentlyContinue) | Where-Object { $_.email } | ForEach-Object { @{ email = "$($_.email)"; sources = $_.sources } } })
                $Result.Source = 'Cache'
                $Result.CheckedAt = ($Rows | Sort-Object Timestamp -Descending | Select-Object -First 1).Timestamp
            }
        } catch {}
    }
    if ($null -eq $Records) { return $Result }

    # Have I Been Pwned's public catalogue: name/title -> title, date, data classes. Cached for a day.
    if (-not $script:CippHibpCatalog -or $script:CippHibpCatalogAt -lt (Get-Date).AddDays(-1)) {
        $script:CippHibpCatalog = @{}
        try {
            foreach ($B in @(Invoke-RestMethod -Uri 'https://haveibeenpwned.com/api/v3/breaches' -Headers @{ 'User-Agent' = 'CIPP-Reports' } -TimeoutSec 60)) {
                $Entry = @{ title = "$($B.Title)"; date = "$($B.BreachDate)"; classes = @($B.DataClasses) }
                foreach ($Key in @("$($B.Name)", "$($B.Title)")) { if ($Key) { $script:CippHibpCatalog[($Key -replace '\s', '').ToLowerInvariant()] = $Entry } }
            }
            $script:CippHibpCatalogAt = Get-Date
        } catch { Write-Information "HIBP breach catalogue unavailable: $($_.Exception.Message)" }
    }

    $Known = @{}
    foreach ($U in @($Users)) {
        foreach ($Address in @($U.userPrincipalName, $U.mail) + @($U.proxyAddresses | ForEach-Object { "$_" -replace '^smtp:', '' })) {
            if ($Address) { $Known["$Address".ToLowerInvariant()] = $true }
        }
    }

    $Accounts = foreach ($Group in ($Records | Group-Object { $_.email.Trim().ToLowerInvariant() })) {
        $Names = @($Group.Group | ForEach-Object {
                $S = $_.sources
                if ($S -is [string]) { $S -split '\s*[,;]\s*' } else { @($S) }
            } | ForEach-Object { "$_".Trim() } | Where-Object { $_ } | Sort-Object -Unique)
        $Breaches = @($Names | ForEach-Object {
                $Match = $script:CippHibpCatalog[($_ -replace '\s', '').ToLowerInvariant()]
                if ($Match) { @{ name = $_; title = $Match.title; date = $Match.date; classes = @($Match.classes) } }
                else { @{ name = $_; title = $_; date = ''; classes = @() } }
            } | Sort-Object { $_.date } -Descending)
        @{
            email    = $Group.Name
            current  = $(if ($Known.Count -gt 0) { $Known.ContainsKey($Group.Name) } else { $null })
            breaches = $Breaches
            passwords = [bool](@($Breaches | Where-Object { @($_.classes) -contains 'Passwords' }).Count -gt 0)
        }
    }
    $Result.Accounts = @($Accounts | Sort-Object { if ($_.current -eq $false) { 1 } else { 0 } }, { $_.email })
    $Result.Total = $Result.Accounts.Count
    $Result.Current = @($Result.Accounts | Where-Object { $_.current -ne $false }).Count
    $Result.WithPasswords = @($Result.Accounts | Where-Object { $_.passwords -and $_.current -ne $false }).Count
    return $Result
}
