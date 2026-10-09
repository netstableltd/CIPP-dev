function Invoke-AteraExtensionSync {
    <#
    .SYNOPSIS
        Pulls Atera data once for the whole account and writes it into the CIPP Reporting DB for
        every mapped tenant.

    .DESCRIPTION
        Runs account-wide rather than once per tenant: Atera's alerts endpoint cannot be filtered
        by customer, so a per-tenant sync would re-read the whole alert history for every tenant.
        One run costs roughly 60-70 API calls for a typical MSP.

        For each tenant mapped on Integrations > Atera > Tenant Mapping, these Reporting DB
        collections are replaced:

          AteraCustomer   - the Atera customer record
          AteraAgents     - every agent (device) for the customer
          AteraAlerts     - alerts created in the last WindowDays days (newest-first paging stops at the cutoff)
          AteraTickets    - tickets created in the last WindowDays days, plus every Open/Pending ticket
          AteraContracts  - every contract for the customer

        Long free-text fields are truncated to keep rows small. The run summary is stored in the
        AteraSettings table (RowKey 'LastSync') for the Reports and Integrations pages.

    .PARAMETER WindowDays
        How far back to collect alerts and tickets. Default 45, so a full calendar month is always
        covered when reports run early in the following month.

    .PARAMETER TenantFilter
        Optional. Limit the write phase to one tenant (default domain or customer id).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [int]$WindowDays = 45,
        [string]$TenantFilter
    )

    $Started = Get-Date
    $SettingsTable = Get-CIPPTable -TableName 'AteraSettings'

    function Limit-Text([string]$Text, [int]$Max = 1000) {
        if ($null -eq $Text) { return $null }
        if ($Text.Length -le $Max) { return $Text }
        return $Text.Substring(0, $Max) + '…'
    }

    try {
        $Mappings = @(Get-ExtensionMapping -Extension 'Atera' | Where-Object { $_.IntegrationId -and $_.IntegrationId -ne '-1' })
        if ($Mappings.Count -eq 0) {
            Write-LogMessage -API 'AteraSync' -tenant 'Global' -message 'Atera sync skipped: no tenants are mapped to Atera customers.' -Sev 'Info'
            return
        }
        $Tenants = Get-Tenants -IncludeErrors
        if ($TenantFilter) {
            $Tenants = $Tenants | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter }
        }

        $Cutoff = (Get-Date).ToUniversalTime().AddDays(-$WindowDays)

        # --- Account-wide pulls -------------------------------------------------------------
        $Customers = @(Invoke-AteraRequest -Path 'customers' -All)
        $Agents = @(Invoke-AteraRequest -Path 'agents' -All)
        $Contracts = @(Invoke-AteraRequest -Path 'contracts' -All)
        $Alerts = @(Invoke-AteraRequest -Path 'alerts' -All -StopWhen { $_.Created -and ([datetime]$_.Created).ToUniversalTime() -lt $Cutoff })
        $RecentTickets = @(Invoke-AteraRequest -Path 'tickets' -All -StopWhen { $_.TicketCreatedDate -and ([datetime]$_.TicketCreatedDate).ToUniversalTime() -lt $Cutoff })
        $OpenTickets = @(Invoke-AteraRequest -Path 'tickets' -All -Query @{ ticketStatus = 'Open' })
        $PendingTickets = @(Invoke-AteraRequest -Path 'tickets' -All -Query @{ ticketStatus = 'Pending' })
        $Tickets = @($RecentTickets + $OpenTickets + $PendingTickets | Sort-Object TicketID -Unique)

        # --- Shape rows (Add-CIPPDbItem keys rows on an 'id' property) -------------------------
        $AgentRows = $Agents | Select-Object *, @{ n = 'id'; e = { "$($_.AgentID)" } }
        $ContractRows = $Contracts | Select-Object *, @{ n = 'id'; e = { "$($_.ContractID)" } }
        $AlertRows = foreach ($Alert in $Alerts) {
            $Row = $Alert | Select-Object * -ExcludeProperty AlertMessage
            $Row | Add-Member -NotePropertyName AlertMessage -NotePropertyValue (Limit-Text $Alert.AlertMessage 1000) -Force
            $Row | Add-Member -NotePropertyName id -NotePropertyValue "$($Alert.AlertID)" -Force
            $Row
        }
        $TicketRows = foreach ($Ticket in $Tickets) {
            $Row = $Ticket | Select-Object * -ExcludeProperty FirstComment, LastEndUserComment, LastTechnicianComment
            $Row | Add-Member -NotePropertyName FirstComment -NotePropertyValue (Limit-Text $Ticket.FirstComment 1000) -Force
            $Row | Add-Member -NotePropertyName LastEndUserComment -NotePropertyValue (Limit-Text $Ticket.LastEndUserComment 500) -Force
            $Row | Add-Member -NotePropertyName LastTechnicianComment -NotePropertyValue (Limit-Text $Ticket.LastTechnicianComment 500) -Force
            $Row | Add-Member -NotePropertyName id -NotePropertyValue "$($Ticket.TicketID)" -Force
            # Atera leaves TotalDurationMinutes at 0 and records time in TotalDurationSeconds; a minutes
            # figure makes the time usable in Report Builder tables and sums.
            $Row | Add-Member -NotePropertyName TimeLoggedMinutes -NotePropertyValue ([int][math]::Round([double]($Ticket.TotalDurationSeconds ?? 0) / 60)) -Force
            $Row
        }

        # --- Write per mapped tenant -------------------------------------------------------
        $Summary = [System.Collections.Generic.List[object]]::new()
        foreach ($Mapping in $Mappings) {
            $Tenant = $Tenants | Where-Object { $_.customerId -eq $Mapping.RowKey } | Select-Object -First 1
            if (-not $Tenant) { continue }
            $CustomerId = [int]$Mapping.IntegrationId
            $Domain = $Tenant.defaultDomainName
            try {
                $Customer = $Customers | Where-Object { $_.CustomerID -eq $CustomerId } | Select-Object -First 1
                if (-not $Customer) {
                    Write-LogMessage -API 'AteraSync' -tenant $Domain -tenantId $Tenant.customerId -message "Atera customer $CustomerId ($($Mapping.IntegrationName)) no longer exists in Atera - check the mapping." -Sev 'Warning'
                    continue
                }
                $TenantAgents = @($AgentRows | Where-Object { $_.CustomerID -eq $CustomerId })
                $TenantAlerts = @($AlertRows | Where-Object { $_.CustomerID -eq $CustomerId })
                $TenantTickets = @($TicketRows | Where-Object { $_.CustomerID -eq $CustomerId })
                $TenantContracts = @($ContractRows | Where-Object { $_.CustomerID -eq $CustomerId })

                Add-CIPPDbItem -TenantFilter $Domain -Type 'AteraCustomer' -Data @($Customer | Select-Object *, @{ n = 'id'; e = { "$($_.CustomerID)" } }) -AddCount -ClearOnEmpty
                Add-CIPPDbItem -TenantFilter $Domain -Type 'AteraAgents' -Data $TenantAgents -AddCount -ClearOnEmpty
                Add-CIPPDbItem -TenantFilter $Domain -Type 'AteraAlerts' -Data $TenantAlerts -AddCount -ClearOnEmpty
                Add-CIPPDbItem -TenantFilter $Domain -Type 'AteraTickets' -Data $TenantTickets -AddCount -ClearOnEmpty
                Add-CIPPDbItem -TenantFilter $Domain -Type 'AteraContracts' -Data $TenantContracts -AddCount -ClearOnEmpty

                $Summary.Add([pscustomobject]@{
                        Tenant    = $Domain
                        Customer  = $Customer.CustomerName
                        Agents    = $TenantAgents.Count
                        Alerts    = $TenantAlerts.Count
                        Tickets   = $TenantTickets.Count
                        Contracts = $TenantContracts.Count
                    })
            } catch {
                $ErrorMessage = Get-CippException -Exception $_
                Write-LogMessage -API 'AteraSync' -tenant $Domain -tenantId $Tenant.customerId -message "Atera sync failed for this tenant: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
            }
        }

        $Duration = [math]::Round(((Get-Date) - $Started).TotalSeconds)
        $Message = "Atera sync complete: $($Summary.Count) tenant(s), $($Agents.Count) agents, $($Alerts.Count) alerts and $($Tickets.Count) tickets read in ${Duration}s (window $WindowDays days)."
        Write-LogMessage -API 'AteraSync' -tenant 'Global' -message $Message -Sev 'Info' -LogData @($Summary)
        Add-CIPPAzDataTableEntity @SettingsTable -Force -Entity @{
            PartitionKey    = 'Atera'
            RowKey          = 'LastSync'
            LastRunTime     = (Get-Date).ToUniversalTime().ToString('o')
            Status          = 'Success'
            Message         = $Message
            TenantSummary   = [string](ConvertTo-Json -InputObject @($Summary) -Depth 3 -Compress)
            DurationSeconds = [int]$Duration
        }
        return $Message
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        $Message = "Atera sync failed: $($ErrorMessage.NormalizedError)"
        Write-LogMessage -API 'AteraSync' -tenant 'Global' -message $Message -Sev 'Error' -LogData $ErrorMessage
        Add-CIPPAzDataTableEntity @SettingsTable -Force -Entity @{
            PartitionKey = 'Atera'
            RowKey       = 'LastSync'
            LastRunTime  = (Get-Date).ToUniversalTime().ToString('o')
            Status       = 'Failed'
            Message      = $Message
        }
        throw
    }
}
