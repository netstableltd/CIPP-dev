function Invoke-AteraRequest {
    <#
    .SYNOPSIS
        Calls the Atera REST API (v3) with paging, auth and rate-limit handling.

    .DESCRIPTION
        Auth: Atera issues two kinds of API key. Older keys are 32-character hex strings sent in an
        X-API-KEY header; newer keys are JWTs (start with "eyJ") and must be sent as
        "Authorization: Bearer <key>" - sending a JWT as X-API-KEY returns 401. The header is chosen
        from the key's shape.

        Paging: list endpoints return { items, page, itemsInPage, totalItemCount, totalPages }.
        With -All every page is fetched (50 items per page, Atera's maximum). With -StopWhen, paging
        stops once an item matches the script block - used for newest-first endpoints (alerts,
        tickets) to stop at a date cutoff instead of reading the whole history.

        Rate limit: Atera allows 700 requests/minute per account. 429 responses are retried with
        back-off (honouring Retry-After when present).

    .PARAMETER Path
        Path under /api/v3, e.g. 'customers' or 'agents/customer/5'.

    .PARAMETER Query
        Extra query string parameters.

    .PARAMETER All
        Fetch every page and return the combined items.

    .PARAMETER StopWhen
        Script block evaluated per item ($_ is the item). When it returns $true for any item on a
        page, items from that page that do NOT match are kept and paging stops.

    .PARAMETER MaxPages
        Safety cap on pages fetched (default 500).

    .EXAMPLE
        Invoke-AteraRequest -Path 'customers' -All

    .EXAMPLE
        $Cutoff = (Get-Date).AddDays(-35).ToUniversalTime()
        Invoke-AteraRequest -Path 'alerts' -All -StopWhen { [datetime]$_.Created -lt $Cutoff }
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [hashtable]$Query = @{},
        [switch]$All,
        [scriptblock]$StopWhen,
        [int]$MaxPages = 500,
        [string]$APIKey
    )

    if (-not $APIKey) { $APIKey = Get-ExtensionAPIKey -Extension 'Atera' }
    if ([string]::IsNullOrWhiteSpace($APIKey)) { throw 'No Atera API key is configured.' }
    $APIKey = $APIKey.Trim()

    $Headers = @{
        'Accept'     = 'application/json'
        'User-Agent' = 'CIPP'
    }
    if ($APIKey.StartsWith('eyJ')) {
        $Headers['Authorization'] = "Bearer $APIKey"
    } else {
        $Headers['X-API-KEY'] = $APIKey
    }

    $BaseUri = 'https://app.atera.com/api/v3/' + $Path.TrimStart('/')

    $Send = {
        param([hashtable]$Params)
        $QueryString = ($Params.GetEnumerator() | Sort-Object Key | ForEach-Object {
                '{0}={1}' -f [uri]::EscapeDataString([string]$_.Key), [uri]::EscapeDataString([string]$_.Value)
            }) -join '&'
        $Uri = if ($QueryString) { "$($BaseUri)?$QueryString" } else { $BaseUri }
        $Attempt = 0
        while ($true) {
            $Attempt++
            try {
                return Invoke-RestMethod -Uri $Uri -Method GET -Headers $Headers -ErrorAction Stop
            } catch {
                $Status = $_.Exception.Response.StatusCode.value__
                if ($Status -eq 429 -and $Attempt -le 5) {
                    $RetryAfter = 0
                    try { $RetryAfter = [int]($_.Exception.Response.Headers.RetryAfter.Delta.TotalSeconds) } catch {}
                    if ($RetryAfter -le 0) { $RetryAfter = [math]::Min(60, [math]::Pow(2, $Attempt) * 2) }
                    Write-Information "Atera rate limited on $Path, waiting $RetryAfter seconds (attempt $Attempt)"
                    Start-Sleep -Seconds $RetryAfter
                    continue
                }
                $Message = $_.Exception.Message
                if ($Status -eq 401) { $Message = 'Atera rejected the API key (401). Check the key in Integrations > Atera.' }
                if ($Status -eq 403) { $Message = "The Atera API key does not have permission for '$Path' (403)." }
                throw "Atera API request to '$Path' failed: $Message"
            }
        }
    }

    if (-not $All) {
        return & $Send $Query
    }

    $Results = [System.Collections.Generic.List[object]]::new()
    $Page = 1
    do {
        $PageQuery = $Query.Clone()
        $PageQuery['page'] = $Page
        $PageQuery['itemsInPage'] = 50
        $Response = & $Send $PageQuery
        $Items = @($Response.items)
        $Stop = $false
        if ($StopWhen) {
            foreach ($Item in $Items) {
                if ($Item | Where-Object $StopWhen) { $Stop = $true } else { $Results.Add($Item) }
            }
        } else {
            foreach ($Item in $Items) { $Results.Add($Item) }
        }
        $TotalPages = [int]($Response.totalPages)
        $Page++
    } while (-not $Stop -and $Page -le $TotalPages -and $Page -le $MaxPages -and $Items.Count -gt 0)

    return $Results.ToArray()
}
