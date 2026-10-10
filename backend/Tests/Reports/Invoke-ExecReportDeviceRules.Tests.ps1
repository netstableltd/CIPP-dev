# Pester tests for the device rules (Reports > Device Rules).
#
# Pins: defaults come from Config/DeviceRatingRules.json; saved thresholds replace the defaults and
# are flagged as changed; only known rules and fields are stored; bad numbers and working hours are
# rejected with 400 and nothing is written; Reset removes the saved row; a user limited to some
# tenants cannot change rules that apply to every company.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }
    $env:CIPPRootPath = $RepoRoot

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$Exception" } }
    $script:AllowedTenants = @('AllTenants')
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:AllowedTenants }

    . (& $Find 'Test-CIPPReportAccess.ps1')
    . (& $Find 'Get-CIPPReportDeviceRules.ps1')
    . (& $Find 'Invoke-ListReportDeviceRules.ps1')
    . (& $Find 'Invoke-ExecReportDeviceRules.ps1')
    . (& $Find 'Resolve-AteraDeviceRules.ps1')

    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"dave@contoso.com"}'))
    function New-RulesRequest($Body) {
        [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecReportDeviceRules' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = $Body }
    }
}

AfterAll { Remove-Item Env:CIPPRootPath -ErrorAction SilentlyContinue }

Describe 'Get-CIPPReportDeviceRules' {
    It 'returns every default rule, marked as default, when nothing is saved' {
        Mock Get-CIPPAzDataTableEntity { $null }
        $R = Get-CIPPReportDeviceRules
        @($R.Rules).Count | Should -BeGreaterThan 10
        $Intel = @($R.Rules) | Where-Object id -EQ 'intelGeneration'
        $Intel.attention | Should -Be 8
        $Intel.check | Should -Be 9
        $Intel.isDefault | Should -BeTrue
    }

    It 'applies saved thresholds over the defaults and flags them as changed' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ Rules = '[{"id":"memoryGB","check":16,"attention":8},{"id":"windowsHome","severity":"off"},{"id":"gone","check":1}]'; ModifiedBy = 'dave@contoso.com' } }
        $R = Get-CIPPReportDeviceRules
        $Mem = @($R.Rules) | Where-Object id -EQ 'memoryGB'
        $Mem.check | Should -Be 16
        $Mem.isDefault | Should -BeFalse
        $Mem.default.check | Should -Be 8
        (@($R.Rules) | Where-Object id -EQ 'windowsHome').severity | Should -Be 'off'
        @($R.Rules | Where-Object id -EQ 'gone').Count | Should -Be 0
        $R.LastModifiedBy | Should -Be 'dave@contoso.com'
    }

    It 'matches the defaults the device rating uses' {
        Mock Get-CIPPAzDataTableEntity { $null }
        $Resolved = Resolve-AteraDeviceRules
        foreach ($Rule in @((Get-CIPPReportDeviceRules).Rules)) {
            "$($Resolved[$Rule.id].check)|$($Resolved[$Rule.id].attention)|$($Resolved[$Rule.id].severity)" | Should -Be "$($Rule.check)|$($Rule.attention)|$($Rule.severity)"
        }
    }
}

Describe 'Invoke-ExecReportDeviceRules' {
    BeforeEach {
        $script:Saved = $null
        $script:Removed = $false
        Mock Get-CIPPAzDataTableEntity { $null }
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
        Mock Remove-AzDataTableEntity { $script:Removed = $true }
    }

    It 'saves known rules only, with blank thresholds as null' {
        $r = Invoke-ExecReportDeviceRules -Request (New-RulesRequest ([pscustomobject]@{ Rules = @(
                        [pscustomobject]@{ id = 'driveFull'; check = '80'; attention = '' }
                        [pscustomobject]@{ id = 'windowsHome'; severity = 'attention' }
                        [pscustomobject]@{ id = 'memoryThreshold'; value = 85 }
                        [pscustomobject]@{ id = 'nonsense'; check = 1 }
                    ) }))
        $r.StatusCode | Should -Be 200
        $Saved.RowKey | Should -Be 'DeviceRules'
        $Rules = @($Saved.Rules | ConvertFrom-Json)
        $Rules.id | Should -Be @('driveFull', 'windowsHome', 'memoryThreshold')
        $Rules[0].check | Should -Be 80
        $Rules[0].attention | Should -BeNullOrEmpty
        $Rules[1].severity | Should -Be 'attention'
        $Rules[2].value | Should -Be 85
    }

    It 'rejects <Case> with 400 and writes nothing' -ForEach @(
        @{ Case = 'a negative threshold'; Rule = @{ id = 'cores'; check = -1; attention = 4 } }
        @{ Case = 'text for a threshold'; Rule = @{ id = 'cores'; check = 'four'; attention = 4 } }
        @{ Case = 'an unknown severity'; Rule = @{ id = 'windowsHome'; severity = 'maybe' } }
        @{ Case = 'a working day that ends before it starts'; Rule = @{ id = 'workdayEnd'; value = 7 } }
        @{ Case = 'a memory threshold over 100%'; Rule = @{ id = 'memoryThreshold'; value = 120 } }
    ) {
        $r = Invoke-ExecReportDeviceRules -Request (New-RulesRequest ([pscustomobject]@{ Rules = @([pscustomobject]$Rule) }))
        $r.StatusCode | Should -Be 400
        $Saved | Should -BeNullOrEmpty
    }

    It 'resets to the defaults by removing the saved row' {
        Mock Get-CIPPAzDataTableEntity { [pscustomobject]@{ PartitionKey = 'Settings'; RowKey = 'DeviceRules' } }
        $r = Invoke-ExecReportDeviceRules -Request (New-RulesRequest ([pscustomobject]@{ Action = 'Reset' }))
        $r.StatusCode | Should -Be 200
        $Removed | Should -BeTrue
    }

    It 'refuses a user limited to some tenants' {
        $script:AllowedTenants = @('t1')
        try {
            $r = Invoke-ExecReportDeviceRules -Request (New-RulesRequest ([pscustomobject]@{ Rules = @([pscustomobject]@{ id = 'cores'; check = 4; attention = 2 }) }))
            $r.StatusCode | Should -Be 403
            $Saved | Should -BeNullOrEmpty
        } finally { $script:AllowedTenants = @('AllTenants') }
    }
}
