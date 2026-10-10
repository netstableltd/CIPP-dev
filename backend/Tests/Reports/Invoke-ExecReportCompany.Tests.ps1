# Pester tests for Reports companies (Get-CIPPReportCompanies, Invoke-ExecReportCompany).
#
# Pins: every tenant is listed with defaults when it has no settings row; "Default" delivery and
# pre-check recipients resolve against the global settings; a save only changes the fields sent
# (so bulk Enable/Disable never wipes recipients); invalid input is rejected with 400.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Get-ExtensionMapping { param($Extension) }
    function Get-Tenants { param([switch]$IncludeErrors) }
    function Get-CIPPReportSettings { [pscustomobject]@{ DefaultDeliveryMode = 'Review'; PrecheckRecipients = 'ops@msp.com'; DefaultSections = @() } }
    function Get-CIPPReportSectionCatalog {
        param([switch]$BuiltInOnly)
        $BuiltIn = @(
            [pscustomobject]@{ value = 'summary'; label = 'Summary' }
            [pscustomobject]@{ value = 'devices'; label = 'Devices (Atera)' }
        )
        if ($BuiltInOnly) { return $BuiltIn }
        $BuiltIn + @([pscustomobject]@{ value = 'template:abc-1'; label = 'Board pack (Report Builder)' })
    }
    $script:AllowedTenants = @('AllTenants')
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:AllowedTenants }
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Test-CIPPReportAccess.ps1' -File | Select-Object -First 1 -ExpandProperty FullName)
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . (& $Find 'ConvertFrom-CIPPReportSectionList.ps1')
    . (& $Find 'Test-CIPPReportSectionId.ps1')
    . (& $Find 'Get-CIPPReportCompanies.ps1')
    . (& $Find 'Invoke-ExecReportCompany.ps1')

    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"dave@msp.com"}'))
    function New-CompanyRequest([hashtable]$Body) {
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecReportCompany' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Get-CIPPReportCompanies' {
    BeforeEach {
        Mock Get-Tenants {
            @(
                [pscustomobject]@{ customerId = 't1'; displayName = 'Contoso'; defaultDomainName = 'contoso.com'; LastGraphError = '' }
                [pscustomobject]@{ customerId = 't2'; displayName = 'Fabrikam'; defaultDomainName = 'fabrikam.com'; LastGraphError = 'AADSTS65001' }
            )
        }
        Mock Get-ExtensionMapping { @([pscustomobject]@{ RowKey = 't1'; IntegrationId = '5'; IntegrationName = 'Contoso Ltd' }) }
        Mock Get-CIPPAzDataTableEntity {
            @([pscustomobject]@{ RowKey = 't1'; Enabled = $true; DeliveryMode = 'Auto'; Recipients = 'boss@contoso.com'; PrecheckRecipients = ''; Sections = '["template:abc-1","summary","template:gone-2"]' })
        }
    }

    It 'returns a company''s sections in order as label/value pairs, flagging deleted templates' {
        $Con = @(Get-CIPPReportCompanies) | Where-Object TenantId -EQ 't1'
        @($Con.Sections).value | Should -Be @('template:abc-1', 'summary', 'template:gone-2')
        @($Con.Sections)[0].label | Should -Be 'Board pack (Report Builder)'
        @($Con.Sections)[2].label | Should -Match 'missing'
        $Con.SectionsSummary | Should -Match '^Board pack'
    }

    It 'shows the default sections for a company with no list of its own' {
        $Fab = @(Get-CIPPReportCompanies) | Where-Object TenantId -EQ 't2'
        @($Fab.Sections).Count | Should -Be 0
        $Fab.SectionsSummary | Should -Be 'Default (All built-in sections)'
    }

    It 'lists every tenant, with defaults for tenants that have no settings' {
        $Rows = @(Get-CIPPReportCompanies)
        $Rows.Count | Should -Be 2
        $Fab = $Rows | Where-Object TenantId -EQ 't2'
        $Fab.Enabled | Should -BeFalse
        $Fab.DeliveryMode | Should -Be 'Default'
        $Fab.EffectiveDeliveryMode | Should -Be 'Review'
        $Fab.EffectivePrecheckRecipients | Should -Be 'ops@msp.com'
    }

    It 'resolves own settings, Atera mapping and data status' {
        $Rows = @(Get-CIPPReportCompanies)
        $Con = $Rows | Where-Object TenantId -EQ 't1'
        $Con.Enabled | Should -BeTrue
        $Con.EffectiveDeliveryMode | Should -Be 'Auto'
        $Con.AteraCustomer | Should -Be 'Contoso Ltd'
        $Con.DataStatus | Should -Be 'OK'
        ($Rows | Where-Object TenantId -EQ 't2').DataStatus | Should -Match 'connection error'
        ($Rows | Where-Object TenantId -EQ 't2').DataStatus | Should -Match 'No Atera mapping'
    }
}

Describe 'Invoke-ExecReportCompany' {
    BeforeEach {
        $script:Saved = $null
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
        Mock Get-Tenants { @([pscustomobject]@{ customerId = 't1'; displayName = 'Contoso'; defaultDomainName = 'contoso.com' }) }
        Mock Get-CIPPAzDataTableEntity {
            [pscustomobject]@{ PartitionKey = 'Company'; RowKey = 't1'; Enabled = $false; Recipients = 'boss@contoso.com'; DeliveryMode = 'Auto'; Timestamp = 'x' }
        }
    }

    It 'refuses a user who has no access to the tenant, and writes nothing' {
        $script:AllowedTenants = @('t9')
        try {
            $r = Invoke-ExecReportCompany -Request (New-CompanyRequest @{ TenantId = 't1'; Action = 'Enable' })
            $r.StatusCode | Should -Be 403
            $Saved | Should -BeNullOrEmpty
        } finally { $script:AllowedTenants = @('AllTenants') }
    }

    It 'allows a user limited to that tenant' {
        $script:AllowedTenants = @('t1')
        try {
            (Invoke-ExecReportCompany -Request (New-CompanyRequest @{ TenantId = 't1'; Action = 'Enable' })).StatusCode | Should -Be 200
        } finally { $script:AllowedTenants = @('AllTenants') }
    }

    It 'Enable only flips Enabled and keeps the other saved fields' {
        $r = Invoke-ExecReportCompany -Request (New-CompanyRequest @{ TenantId = 't1'; Action = 'Enable' })
        $r.StatusCode | Should -Be 200
        $Saved.Enabled | Should -BeTrue
        $Saved.Recipients | Should -Be 'boss@contoso.com'
        $Saved.DeliveryMode | Should -Be 'Auto'
        $Saved.ContainsKey('Timestamp') | Should -BeFalse
        $Saved.ModifiedBy | Should -Be 'dave@msp.com'
    }

    It 'saves edited fields, unwrapping autocomplete values and normalising recipients' {
        $r = Invoke-ExecReportCompany -Request (New-CompanyRequest @{
                TenantId     = 't1'
                Enabled      = $true
                Recipients   = 'a@contoso.com; b@contoso.com'
                DeliveryMode = @{ label = 'Review'; value = 'Review' }
                ScheduleMode = @{ label = 'Custom'; value = 'Custom' }
                ReportDay    = 3
            })
        $r.StatusCode | Should -Be 200
        $Saved.Recipients | Should -Be 'a@contoso.com, b@contoso.com'
        $Saved.DeliveryMode | Should -Be 'Review'
        $Saved.ScheduleMode | Should -Be 'Custom'
        $Saved.ReportDay | Should -Be 3
    }

    It 'stores a paused-until date from unix seconds' {
        $r = Invoke-ExecReportCompany -Request (New-CompanyRequest @{ TenantId = 't1'; ScheduleMode = 'Paused'; PausedUntil = 1798761600 })
        $r.StatusCode | Should -Be 200
        $Saved.PausedUntil | Should -Be '2027-01-01'
    }

    It 'saves report sections in the order chosen, keeping other fields' {
        $r = Invoke-ExecReportCompany -Request (New-CompanyRequest @{
                TenantId = 't1'
                Sections = @(@{ label = 'Board pack'; value = 'template:abc-1' }, @{ label = 'Summary'; value = 'summary' })
            })
        $r.StatusCode | Should -Be 200
        $Saved.Sections | Should -Be '["template:abc-1","summary"]'
        $Saved.Recipients | Should -Be 'boss@contoso.com'
    }

    It 'clears report sections (back to default) when an empty list is sent' {
        $r = Invoke-ExecReportCompany -Request (New-CompanyRequest @{ TenantId = 't1'; Sections = @() })
        $r.StatusCode | Should -Be 200
        $Saved.Sections | Should -Be ''
    }

    It 'rejects <Case>' -ForEach @(
        @{ Case = 'an unknown section'; Body = @{ TenantId = 't1'; Sections = @('nonsense') } }
        @{ Case = 'an unknown tenant'; Body = @{ TenantId = 'nope'; Action = 'Enable' } }
        @{ Case = 'a bad recipient'; Body = @{ TenantId = 't1'; Recipients = 'not-an-email' } }
        @{ Case = 'a custom schedule without a day'; Body = @{ TenantId = 't1'; ScheduleMode = 'Custom'; ReportDay = '' } }
        @{ Case = 'a pause without a date'; Body = @{ TenantId = 't1'; ScheduleMode = 'Paused' } }
        @{ Case = 'an unknown delivery mode'; Body = @{ TenantId = 't1'; DeliveryMode = 'Sometimes' } }
        @{ Case = 'a request with nothing to change'; Body = @{ TenantId = 't1' } }
    ) {
        $r = Invoke-ExecReportCompany -Request (New-CompanyRequest $Body)
        $r.StatusCode | Should -Be 400
        $Saved | Should -BeNullOrEmpty
    }
}
