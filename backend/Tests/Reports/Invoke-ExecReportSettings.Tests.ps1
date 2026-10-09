# Pester tests for the Reports settings endpoints.
#
# Pins: defaults are returned when nothing is saved; a valid save writes one normalised row
# (autocomplete { label, value } objects unwrapped, recipients trimmed and joined); invalid
# input is rejected with 400 and nothing is written; the customer-send switch is stored as a bool.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) {
        $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode])
    }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }

    . (& $Find 'ConvertFrom-CIPPReportSectionList.ps1')
    . (& $Find 'Get-CIPPReportSectionCatalog.ps1')
    . (& $Find 'Test-CIPPReportSectionId.ps1')
    . (& $Find 'Get-CIPPReportSettings.ps1')
    . (& $Find 'Invoke-ListReportSettings.ps1')
    . (& $Find 'Invoke-ExecReportSettings.ps1')

    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"dave@contoso.com"}'))
    function New-SettingsRequest {
        param([hashtable]$Overrides = @{})
        $Body = [ordered]@{
            PrecheckRecipients  = ' ops@contoso.com; dave@contoso.com '
            PrecheckLeadDays    = 5
            ReportDayMode       = @{ label = 'First working day of the month'; value = 'FirstWorkingDay' }
            ReportDay           = 1
            SendTime            = '09:00'
            TimeZone            = @{ label = 'UTC'; value = 'UTC' }
            DefaultDeliveryMode = @{ label = 'Review'; value = 'Review' }
            CustomerSendEnabled = $false
        }
        foreach ($k in $Overrides.Keys) { $Body[$k] = $Overrides[$k] }
        [pscustomobject]@{
            Params  = @{ CIPPEndpoint = 'ExecReportSettings' }
            Headers = @{ 'x-ms-client-principal' = $Principal }
            Body    = [pscustomobject]$Body
        }
    }
}

Describe 'Get-CIPPReportSettings' {
    It 'returns defaults when nothing has been saved' {
        Mock Get-CIPPAzDataTableEntity { $null }
        $s = Get-CIPPReportSettings
        $s.ReportDayMode | Should -Be 'FirstWorkingDay'
        $s.PrecheckLeadDays | Should -Be 5
        $s.DefaultDeliveryMode | Should -Be 'Review'
        $s.CustomerSendEnabled | Should -BeFalse
        $s.TimeZone | Should -Be 'Europe/London'
    }

    It 'prefers saved values over defaults' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PrecheckLeadDays = '3'; CustomerSendEnabled = 'True'; ModifiedBy = 'x' } }
        $s = Get-CIPPReportSettings
        $s.PrecheckLeadDays | Should -Be 3
        $s.CustomerSendEnabled | Should -BeTrue
        $s.ReportDayMode | Should -Be 'FirstWorkingDay'
    }

    It 'returns default sections as an ordered id array (empty when not set)' {
        Mock Get-CIPPAzDataTableEntity { $null }
        @((Get-CIPPReportSettings).DefaultSections).Count | Should -Be 0
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ DefaultSections = '["devices","template:abc-1","summary"]' } }
        (Get-CIPPReportSettings).DefaultSections | Should -Be @('devices', 'template:abc-1', 'summary')
    }
}

Describe 'Invoke-ExecReportSettings' {
    BeforeEach {
        $script:Saved = $null
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
    }

    It 'saves a valid request as one normalised row' {
        $r = Invoke-ExecReportSettings -Request (New-SettingsRequest)
        $r.StatusCode | Should -Be 200
        $Saved.PartitionKey | Should -Be 'Settings'
        $Saved.RowKey | Should -Be 'Global'
        $Saved.PrecheckRecipients | Should -Be 'ops@contoso.com, dave@contoso.com'
        $Saved.ReportDayMode | Should -Be 'FirstWorkingDay'
        $Saved.TimeZone | Should -Be 'UTC'
        $Saved.DefaultDeliveryMode | Should -Be 'Review'
        $Saved.CustomerSendEnabled | Should -BeFalse
        $Saved.ModifiedBy | Should -Be 'dave@contoso.com'
    }

    It 'stores the customer-send switch as a boolean and says so' {
        $r = Invoke-ExecReportSettings -Request (New-SettingsRequest @{ CustomerSendEnabled = $true })
        $Saved.CustomerSendEnabled | Should -BeTrue
        $r.Body.Results | Should -Match 'ENABLED'
    }

    It 'saves default sections in the order given, as JSON' {
        $Sections = @(
            [pscustomobject]@{ label = 'Devices (Atera)'; value = 'devices' }
            [pscustomobject]@{ label = 'Board pack (Report Builder)'; value = 'template:0b6c-44aa' }
            [pscustomobject]@{ label = 'Summary'; value = 'summary' }
            [pscustomobject]@{ label = 'Devices (Atera)'; value = 'devices' }
        )
        $r = Invoke-ExecReportSettings -Request (New-SettingsRequest @{ DefaultSections = $Sections })
        $r.StatusCode | Should -Be 200
        $Saved.DefaultSections | Should -Be '["devices","template:0b6c-44aa","summary"]'
    }

    It 'saves an empty default section list as blank (all built-in sections)' {
        $null = Invoke-ExecReportSettings -Request (New-SettingsRequest @{ DefaultSections = @() })
        $Saved.DefaultSections | Should -Be ''
    }

    It 'rejects <Case> with 400 and writes nothing' -ForEach @(
        @{ Case = 'an unknown section'; Overrides = @{ DefaultSections = @(@{ label = 'x'; value = 'bogus' }) } }
        @{ Case = 'a malformed template section'; Overrides = @{ DefaultSections = @('template:../../etc') } }
        @{ Case = 'a bad email'; Overrides = @{ PrecheckRecipients = 'not-an-email' } }
        @{ Case = 'a bad time'; Overrides = @{ SendTime = '25:00' } }
        @{ Case = 'an unknown delivery mode'; Overrides = @{ DefaultDeliveryMode = @{ value = 'Sometimes' } } }
        @{ Case = 'a day of month out of range'; Overrides = @{ ReportDayMode = @{ value = 'DayOfMonth' }; ReportDay = 31 } }
        @{ Case = 'a lead time out of range'; Overrides = @{ PrecheckLeadDays = 0 } }
        @{ Case = 'an unknown time zone'; Overrides = @{ TimeZone = @{ value = 'Mars/Olympus' } } }
    ) {
        $r = Invoke-ExecReportSettings -Request (New-SettingsRequest $Overrides)
        $r.StatusCode | Should -Be 400
        $Saved | Should -BeNullOrEmpty
    }
}
