# Pester tests for the Atera integration (Modules/CippExtensions/Public/Atera).
#
# Pins: the auth header follows the key format (JWT -> Bearer, hex -> X-API-KEY); paging reads
# every page and StopWhen stops at a newest-first cutoff; auto-mapping prefers domain matches,
# falls back to normalised names, skips ambiguous matches and never overwrites an existing
# mapping; the account-wide sync writes each mapped tenant only its own customer's data.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $AteraDir = Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Directory -Filter 'Atera' |
        Where-Object { $_.FullName -match 'CippExtensions' } | Select-Object -First 1 -ExpandProperty FullName
    if (-not $AteraDir) { throw 'Could not locate the Atera extension folder' }

    function Get-ExtensionAPIKey { param($Extension) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Add-CIPPDbItem { param($TenantFilter, $Type, $Data, [switch]$AddCount, [switch]$ClearOnEmpty) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    Get-ChildItem $AteraDir -Filter *.ps1 | ForEach-Object { . $_.FullName }
}

Describe 'Invoke-AteraRequest' {
    It 'sends a JWT key as a Bearer token' {
        Mock Invoke-RestMethod { $script:SentHeaders = $Headers; [pscustomobject]@{ items = @(); totalPages = 1 } }
        $null = Invoke-AteraRequest -Path 'customers' -APIKey 'eyJhbGciOiJIUzUxMiJ9.e30.sig'
        $SentHeaders['Authorization'] | Should -Be 'Bearer eyJhbGciOiJIUzUxMiJ9.e30.sig'
        $SentHeaders.ContainsKey('X-API-KEY') | Should -BeFalse
        $SentHeaders['User-Agent'] | Should -Not -BeNullOrEmpty
    }

    It 'sends a classic hex key as X-API-KEY' {
        Mock Invoke-RestMethod { $script:SentHeaders = $Headers; [pscustomobject]@{ items = @(); totalPages = 1 } }
        $null = Invoke-AteraRequest -Path 'customers' -APIKey '0123456789abcdef0123456789abcdef'
        $SentHeaders['X-API-KEY'] | Should -Be '0123456789abcdef0123456789abcdef'
        $SentHeaders.ContainsKey('Authorization') | Should -BeFalse
    }

    It 'reads every page with -All' {
        Mock Invoke-RestMethod {
            $p = [int]([regex]::Match($Uri, 'page=(\d+)').Groups[1].Value)
            [pscustomobject]@{ items = @(1..50 | ForEach-Object { [pscustomobject]@{ n = ($p - 1) * 50 + $_ } }); totalPages = 3 }
        }
        $Items = Invoke-AteraRequest -Path 'agents' -All -APIKey 'k'
        $Items.Count | Should -Be 150
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
    }

    It 'stops paging at the first item matching -StopWhen and keeps the newer ones' {
        $Now = Get-Date
        Mock Invoke-RestMethod {
            $p = [int]([regex]::Match($Uri, 'page=(\d+)').Groups[1].Value)
            $Base = $Now.AddDays( - ($p - 1) * 10)
            [pscustomobject]@{ items = @(0..9 | ForEach-Object { [pscustomobject]@{ Created = $Base.AddDays(-$_).ToString('o') } }); totalPages = 99 }
        }
        $Cutoff = $Now.AddDays(-25)
        $Items = Invoke-AteraRequest -Path 'alerts' -All -APIKey 'k' -StopWhen { [datetime]$_.Created -lt $Cutoff }
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly
        $Items.Count | Should -Be 26
        ($Items | Where-Object { [datetime]$_.Created -lt $Cutoff }).Count | Should -Be 0
    }

    It 'throws a clear error when no key is configured' {
        Mock Get-ExtensionAPIKey { '' }
        { Invoke-AteraRequest -Path 'customers' } | Should -Throw '*No Atera API key*'
    }
}

Describe 'Invoke-AteraAutoMap' {
    BeforeEach {
        $script:Written = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:Written.Add($Entity) }
        Mock Get-Tenants {
            @(
                [pscustomobject]@{ customerId = 't1'; displayName = 'Contoso Ltd'; defaultDomainName = 'contoso.co.uk'; initialDomainName = 'contoso.onmicrosoft.com' }
                [pscustomobject]@{ customerId = 't2'; displayName = 'Fabrikam Limited'; defaultDomainName = 'fabrikam.com'; initialDomainName = 'fab.onmicrosoft.com' }
                [pscustomobject]@{ customerId = 't3'; displayName = 'Twin Co'; defaultDomainName = 'twin.com'; initialDomainName = 'twin.onmicrosoft.com' }
                [pscustomobject]@{ customerId = 't4'; displayName = 'Already Mapped'; defaultDomainName = 'mapped.com'; initialDomainName = 'mapped.onmicrosoft.com' }
            )
        }
        Mock Invoke-AteraRequest {
            @(
                [pscustomobject]@{ CustomerID = 1; CustomerName = 'Contoso Trading'; Domain = 'contoso.co.uk' }   # domain match, name differs
                [pscustomobject]@{ CustomerID = 2; CustomerName = 'The Fabrikam'; Domain = '' }                  # name match only
                [pscustomobject]@{ CustomerID = 3; CustomerName = 'Twin A'; Domain = 'twin.com' }                # ambiguous domain
                [pscustomobject]@{ CustomerID = 4; CustomerName = 'Twin B'; Domain = 'twin.com; other.com' }
                [pscustomobject]@{ CustomerID = 5; CustomerName = 'Something Else'; Domain = 'mapped.com' }
            )
        }
        Mock Get-ExtensionMapping { @([pscustomobject]@{ RowKey = 't4'; IntegrationId = '99'; IntegrationName = 'Existing' }) }
    }

    It 'maps by domain first, then by name, skips ambiguous and leaves existing mappings alone' {
        $Message = Invoke-AteraAutoMap -CIPPMapping @{}
        ($Written | Where-Object RowKey -EQ 't1').IntegrationId | Should -Be '1'
        ($Written | Where-Object RowKey -EQ 't2').IntegrationId | Should -Be '2'
        ($Written | Where-Object RowKey -EQ 't3') | Should -BeNullOrEmpty
        ($Written | Where-Object RowKey -EQ 't4') | Should -BeNullOrEmpty
        $Written.Count | Should -Be 2
        $Message | Should -Match 'mapped 2'
        $Message | Should -Match 'skipped 1'
    }
}

Describe 'Invoke-AteraExtensionSync' {
    BeforeEach {
        $script:DbWrites = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPDbItem { $script:DbWrites.Add([pscustomobject]@{ Tenant = $TenantFilter; Type = $Type; Data = @($Data) }) }
        Mock Add-CIPPAzDataTableEntity {}
        Mock Get-ExtensionMapping {
            @(
                [pscustomobject]@{ RowKey = 't1'; IntegrationId = '1'; IntegrationName = 'Contoso' }
                [pscustomobject]@{ RowKey = 't2'; IntegrationId = '2'; IntegrationName = 'Fabrikam' }
            )
        }
        Mock Get-Tenants {
            @(
                [pscustomobject]@{ customerId = 't1'; defaultDomainName = 'contoso.co.uk' }
                [pscustomobject]@{ customerId = 't2'; defaultDomainName = 'fabrikam.com' }
            )
        }
        $Recent = (Get-Date).ToUniversalTime().AddDays(-1).ToString('o')
        Mock Invoke-AteraRequest {
            switch ($Path) {
                'customers' { @([pscustomobject]@{ CustomerID = 1; CustomerName = 'Contoso' }, [pscustomobject]@{ CustomerID = 2; CustomerName = 'Fabrikam' }) }
                'agents' { @([pscustomobject]@{ AgentID = 10; CustomerID = 1 }, [pscustomobject]@{ AgentID = 11; CustomerID = 1 }, [pscustomobject]@{ AgentID = 20; CustomerID = 2 }) }
                'contracts' { @([pscustomobject]@{ ContractID = 100; CustomerID = 2 }) }
                'alerts' { @([pscustomobject]@{ AlertID = 1000; CustomerID = 1; Created = $Recent; AlertMessage = ('x' * 5000) }) }
                'tickets' {
                    if ($Query.ticketStatus -eq 'Open') { @([pscustomobject]@{ TicketID = 501; CustomerID = 2; TicketCreatedDate = '2024-01-01T00:00:00Z' }) }
                    elseif ($Query.ticketStatus -eq 'Pending') { @() }
                    else { @([pscustomobject]@{ TicketID = 500; CustomerID = 1; TicketCreatedDate = $Recent; FirstComment = 'hello' }) }
                }
            }
        }
    }

    It 'writes each mapped tenant only its own customer data' {
        $null = Invoke-AteraExtensionSync
        $Contoso = $DbWrites | Where-Object Tenant -EQ 'contoso.co.uk'
        $Fabrikam = $DbWrites | Where-Object Tenant -EQ 'fabrikam.com'
        ($Contoso | Where-Object Type -EQ 'AteraAgents').Data.AgentID | Should -Be @(10, 11)
        ($Fabrikam | Where-Object Type -EQ 'AteraAgents').Data.AgentID | Should -Be @(20)
        ($Contoso | Where-Object Type -EQ 'AteraContracts').Data | Should -BeNullOrEmpty
        ($Fabrikam | Where-Object Type -EQ 'AteraContracts').Data.ContractID | Should -Be @(100)
        ($Contoso | Where-Object Type -EQ 'AteraTickets').Data.TicketID | Should -Be @(500)
        ($Fabrikam | Where-Object Type -EQ 'AteraTickets').Data.TicketID | Should -Be @(501)
    }

    It 'gives every row an id and truncates long alert text' {
        $null = Invoke-AteraExtensionSync
        $Alert = ($DbWrites | Where-Object { $_.Tenant -eq 'contoso.co.uk' -and $_.Type -eq 'AteraAlerts' }).Data[0]
        $Alert.id | Should -Be '1000'
        $Alert.AlertMessage.Length | Should -BeLessOrEqual 1001
        ($DbWrites | Where-Object Type -EQ 'AteraAgents').Data.id | Should -Contain '10'
    }

    It 'writes all five collections for each mapped tenant' {
        $null = Invoke-AteraExtensionSync
        ($DbWrites | Where-Object Tenant -EQ 'fabrikam.com').Type | Sort-Object | Should -Be @('AteraAgents', 'AteraAlerts', 'AteraContracts', 'AteraCustomer', 'AteraTickets')
    }

    It 'does nothing when no tenants are mapped' {
        Mock Get-ExtensionMapping { @() }
        $null = Invoke-AteraExtensionSync
        $DbWrites.Count | Should -Be 0
        Should -Invoke Invoke-AteraRequest -Times 0
    }
}
