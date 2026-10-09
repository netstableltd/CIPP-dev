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

    It 'rejects <Case> with 400 and writes nothing' -ForEach @(
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
