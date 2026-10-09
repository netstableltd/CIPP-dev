# Pester tests for the Reports customer report and pre-check (synthetic data only).
#
# Pins: period maths; the data gatherer's MFA / device / ticket shaping; each pre-check rule and
# its severity; both trees render to a real PDF with the CIPP renderer; generation stores the PDF
# where Generated Reports reads it, marks tests, and emails only the addresses it is given.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    $Bin = Join-Path $RepoRoot 'Shared/CIPPSharp/bin'
    foreach ($Dll in 'OfficeIMO.Core.dll', 'OfficeIMO.Pdf.dll', 'CIPPSharp.dll') { [void][System.Reflection.Assembly]::LoadFrom((Join-Path $Bin $Dll)) }
    $Modules = Join-Path $RepoRoot 'Modules'
    Get-ChildItem (Get-ChildItem $Modules -Recurse -Directory -Filter 'Reporting' | Select-Object -First 1).FullName -Filter *.ps1 | ForEach-Object { . $_.FullName }
    . (Get-ChildItem $Modules -Recurse -Filter 'ConvertTo-CippReportPdf.ps1' | Select-Object -First 1).FullName
    foreach ($Name in 'Get-CIPPReportPeriod', 'Get-CIPPCustomerReportData', 'Get-CIPPReportFindings', 'Build-CippCustomerReportTree', 'Build-CippReportPrecheckTree', 'Invoke-CIPPReportGeneration', 'ConvertFrom-CIPPReportSectionList', 'Get-CIPPReportSectionCatalog', 'Resolve-CIPPReportSections') {
        . (Get-ChildItem $Modules -Recurse -Filter "$Name.ps1" | Select-Object -First 1).FullName
    }

    function Get-CIPPBrandingSettings { @{ colour = '#1F4E79' } }
    function Get-CIPPBrandingPreset { param($Id) }
    function Get-CIPPTextReplacement { param($Text, $TenantFilter, [switch]$EscapeForJson) $Text }
    function Get-CIPPTable { param($TableName) @{ TableName = $TableName } }
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $TenantFilter, $altEmail, $Attachments, $APIName) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $Sev, $LogData) }
    function Get-CIPPReportSettings { [pscustomobject]@{ TimeZone = 'UTC'; CustomerSendEnabled = $false; DefaultSections = @() } }
    # Report Builder block resolution is covered by upstream's tests; here it passes blocks through
    # with a marker so the tests can see the tenant was applied.
    function Resolve-CippReportBuilderBlocks { param($Blocks, $TenantFilter) @($Blocks | ForEach-Object { $b = [ordered]@{}; foreach ($p in $_.PSObject.Properties) { $b[$p.Name] = $p.Value }; $b.content = "$($b.content)<p>for $TenantFilter</p>"; $b }) }
    $script:TemplateRow = [pscustomobject]@{ PartitionKey = 'ReportBuilderTemplate'; RowKey = 'abc-1'; JSON = (ConvertTo-Json -Depth 10 -InputObject @{ Name = 'Board pack'; Blocks = @(@{ type = 'blank'; title = 'Board notes'; content = '<p>Quarterly board notes</p>' }) }) }
    $script:PageTitles = { param($Blocks) @($Blocks | Where-Object { $_.type -eq 'page' } | ForEach-Object { $_.title }) }
    function Get-Tenants { param([switch]$IncludeErrors) [pscustomobject]@{ customerId = 't1'; displayName = 'Contoso Ltd'; defaultDomainName = 'contoso.com'; LastGraphError = '' } }

    $script:Now = [datetime]'2026-10-09T12:00:00Z'
    $script:Db = @{
        Users           = @(
            @{ accountEnabled = $true; userType = 'Member'; assignedLicenses = @(@{ skuId = 'a' }) }
            @{ accountEnabled = $true; userType = 'Member'; assignedLicenses = @(@{ skuId = 'a' }) }
            @{ accountEnabled = $true; userType = 'Member'; assignedLicenses = @() }
            @{ accountEnabled = $false; userType = 'Member'; assignedLicenses = @() }
        )
        Guests          = @(@{ id = 'g1' })
        MFAState        = @(
            @{ AccountEnabled = $true; UserType = 'Member'; DisplayName = 'Admin Ann'; UPN = 'ann@contoso.com'; IsAdmin = $true; isLicensed = $true; CoveredByCA = 'Not Enforced'; CoveredBySD = $false; PerUser = 'Disabled'; MFARegistration = $true }
            @{ AccountEnabled = $true; UserType = 'Member'; DisplayName = 'Bob'; UPN = 'bob@contoso.com'; IsAdmin = $false; isLicensed = $true; CoveredByCA = 'Enforced - Policy'; CoveredBySD = $false; PerUser = 'Disabled'; MFARegistration = $true }
            @{ AccountEnabled = $true; UserType = 'Member'; DisplayName = 'Cat'; UPN = 'cat@contoso.com'; IsAdmin = $false; isLicensed = $true; CoveredByCA = 'Not Enforced'; CoveredBySD = $true; PerUser = 'Disabled'; MFARegistration = $false }
        )
        SecureScore     = @(
            @{ createdDateTime = '2026-09-01T00:00:00Z'; currentScore = 60; maxScore = 100; averageComparativeScores = @() }
            @{ createdDateTime = '2026-10-08T00:00:00Z'; currentScore = 50; maxScore = 100; averageComparativeScores = @(@{ basis = 'TotalSeats'; averageScore = 45 }) }
        )
        LicenseOverview = @(
            @{ License = 'Business Premium'; CountUsed = 2; TotalLicenses = 5; CountAvailable = 3 }
            @{ License = 'Free Thing'; CountUsed = 0; TotalLicenses = 10000; CountAvailable = 10000 }
        )
        AteraCustomer   = @(@{ CustomerID = 5; CustomerName = 'Contoso' })
        AteraAgents     = @(
            @{ MachineName = 'PC1'; DeviceType = 'PC'; OS = 'Microsoft Windows 11 Pro'; Online = $true; LastSeen = '2026-10-09T10:00:00Z'; LastRebootTime = '2026-08-01T00:00:00Z'; HardwareDisks = @(@{ Drive = 'C:'; Free = 5; Total = 100 }); LastLoginUser = 'bob' }
            @{ MachineName = 'PC2'; DeviceType = 'PC'; OS = 'Microsoft Windows 10 Pro'; Online = $false; LastSeen = '2026-10-08T10:00:00Z'; LastRebootTime = '2026-10-07T00:00:00Z'; HardwareDisks = @(@{ Drive = 'C:'; Free = 60; Total = 100 }) }
            @{ MachineName = 'OLD'; DeviceType = 'PC'; OS = 'Microsoft Windows 7 Professional'; Online = $false; LastSeen = '2025-01-01T00:00:00Z'; LastRebootTime = '2025-01-01T00:00:00Z'; HardwareDisks = @() }
        )
        AteraAlerts     = @(
            @{ Created = '2026-09-10T00:00:00Z'; Severity = 'Warning'; Title = 'Disk Usage'; DeviceName = 'PC1' }
            @{ Created = '2026-09-11T00:00:00Z'; Severity = 'Critical'; Title = 'Disk Usage'; DeviceName = 'PC1' }
            @{ Created = '2026-10-02T00:00:00Z'; Severity = 'Warning'; Title = 'Outside period'; DeviceName = 'PC2' }
        )
        AteraTickets    = @(
            @{ TicketID = 101; TicketTitle = 'Printer'; TicketStatus = 'Closed'; TicketCreatedDate = '2026-09-05T09:00:00Z'; TotalDurationSeconds = 1800; TicketPriority = 'Low' }
            @{ TicketID = 102; TicketTitle = 'No time'; TicketStatus = 'Closed'; TicketCreatedDate = '2026-09-06T09:00:00Z'; TotalDurationSeconds = 0; TicketPriority = 'Low' }
            @{ TicketID = 90; TicketTitle = 'Old urgent'; TicketStatus = 'Open'; TicketCreatedDate = '2026-08-30T09:00:00Z'; TotalDurationSeconds = 600; TicketPriority = 'High' }
        )
        AteraContracts  = @(@{ ContractName = 'Support'; ContractType = 'RetainerFlatFee'; Active = $true; EndDate = '2026-11-01T00:00:00Z' })
    }
    function New-CIPPDbRequest { param($TenantFilter, $Type, $Fields) if ($script:Db.ContainsKey($Type)) { $script:Db[$Type] | ForEach-Object { [pscustomobject]$_ } } else { @() } }
    $script:Period = Get-CIPPReportPeriod -Period 'LastMonth' -Now $script:Now
}

Describe 'Get-CIPPReportPeriod' {
    It 'LastMonth is the previous calendar month' {
        $P = Get-CIPPReportPeriod -Period 'LastMonth' -Now ([datetime]'2026-01-15T00:00:00Z')
        $P.Key | Should -Be '2025-12'
        $P.Label | Should -Be 'December 2025'
        $P.Start | Should -Be ([datetime]'2025-12-01T00:00:00Z')
        $P.End | Should -Be ([datetime]'2026-01-01T00:00:00Z')
        $P.IsPartial | Should -BeFalse
    }
    It 'ThisMonth runs to now and is partial' {
        $P = Get-CIPPReportPeriod -Period 'ThisMonth' -Now $Now
        $P.Key | Should -Be '2026-10'
        $P.IsPartial | Should -BeTrue
        $P.Label | Should -Match 'to date'
    }
    It 'rejects nonsense' { { Get-CIPPReportPeriod -Period 'Soon' } | Should -Throw }
}

Describe 'Get-CIPPCustomerReportData' {
    BeforeAll { $script:Data = Get-CIPPCustomerReportData -TenantFilter 'contoso.com' -Period $Period -Now $Now }
    It 'counts users and licences, ignoring free SKUs' {
        $Data.M365.Users | Should -Be 3
        $Data.M365.Licensed | Should -Be 2
        $Data.M365.Guests | Should -Be 1
        $Data.M365.Unassigned | Should -Be 3
        @($Data.M365.Licences).Count | Should -Be 1
    }
    It 'uses CIPP''s MFA definition (CA, Security Defaults or per-user)' {
        $Data.M365.Mfa.Users | Should -Be 3
        $Data.M365.Mfa.Unprotected | Should -Be 1
        $Data.M365.Mfa.UnprotectedAdmins | Should -Be @('Admin Ann')
    }
    It 'measures the Secure Score change against the start of the period' {
        $Data.M365.SecureScore.Percent | Should -Be 50
        $Data.M365.SecureScore.Change | Should -Be -10
    }
    It 'classifies devices' {
        $Data.Atera.Devices.Total | Should -Be 3
        $Data.Atera.Devices.Active | Should -Be 2
        @($Data.Atera.Devices.NotSeen30).name | Should -Be @('OLD')
        @($Data.Atera.Devices.Unsupported).name | Should -Be @('PC2')
        @($Data.Atera.Devices.LowDisk).name | Should -Be @('PC1')
        @($Data.Atera.Devices.NotRebooted30).name | Should -Be @('PC1')
    }
    It 'keeps alerts and tickets to the period' {
        $Data.Atera.Alerts.Total | Should -Be 2
        $Data.Atera.Tickets.Opened | Should -Be 2
        $Data.Atera.Tickets.MinutesLogged | Should -Be 30
        $Data.Atera.Tickets.OpenNow | Should -Be 1
    }
}

Describe 'Get-CIPPReportFindings' {
    BeforeAll {
        $script:Data = Get-CIPPCustomerReportData -TenantFilter 'contoso.com' -Period $Period -Now $Now
        $script:F = Get-CIPPReportFindings -Data $Data -AteraEnabled $true
        $script:ById = @{}; foreach ($x in $F) { $ById[$x.Id] = $x }
    }
    It 'raises <Id> as <Severity>' -ForEach @(
        @{ Id = 'mfa-admins'; Severity = 'Fix' }
        @{ Id = 'mfa-users'; Severity = 'Fix' }
        @{ Id = 'securescore-drop'; Severity = 'Fix' }
        @{ Id = 'licences-unassigned'; Severity = 'Info' }
        @{ Id = 'devices-stale'; Severity = 'Fix' }
        @{ Id = 'devices-unsupported-os'; Severity = 'Fix' }
        @{ Id = 'devices-low-disk'; Severity = 'Fix' }
        @{ Id = 'devices-no-reboot'; Severity = 'Fix' }
        @{ Id = 'tickets-old-urgent'; Severity = 'Fix' }
        @{ Id = 'tickets-no-time'; Severity = 'Fix' }
        @{ Id = 'contracts-ending'; Severity = 'Info' }
    ) {
        $ById.ContainsKey($Id) | Should -BeTrue -Because "rule $Id should fire on the sample data"
        $ById[$Id].Severity | Should -Be $Severity
    }
    It 'keeps internal-only findings out of the customer wording' {
        $ById['devices-stale'].Customer | Should -BeNullOrEmpty
        $ById['tickets-no-time'].Customer | Should -BeNullOrEmpty
        $ById['devices-low-disk'].Customer | Should -Not -BeNullOrEmpty
    }
    It 'blocks when the tenant has a connection error or no Atera mapping' {
        $Broken = Get-CIPPReportFindings -Data @{ GraphError = 'AADSTS65001'; M365 = $null; Atera = $null } -AteraEnabled $true
        @($Broken | Where-Object Severity -EQ 'Block').Id | Sort-Object | Should -Be @('atera-mapping', 'm365-connection')
        @(Get-CIPPReportFindings -Data @{ GraphError = ''; M365 = @{}; Atera = $null } -AteraEnabled $false | Where-Object Id -EQ 'atera-mapping').Count | Should -Be 0
    }
}

Describe 'Report trees' {
    BeforeAll {
        $script:Data = Get-CIPPCustomerReportData -TenantFilter 'contoso.com' -Period $Period -Now $Now
        $script:F = Get-CIPPReportFindings -Data $Data -AteraEnabled $true
    }
    It 'customer report renders to a PDF and lists only customer-facing actions' {
        $T = Build-CippCustomerReportTree -Data $Data -Findings $F -Summary 'Hello'
        $T.Variables.coverlabel | Should -Be 'Monthly IT Report'
        $Bytes = ConvertTo-CippReportPdf -Blocks $T.Blocks -Variables $T.Variables -TenantName 'Contoso' -ReportName 'T'
        [Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
        $Json = $T.Blocks | ConvertTo-Json -Depth 20
        $Json | Should -Match 'Turn on multi-factor authentication for every administrator'
        $Json | Should -Not -Match 'not checked in to Atera'
    }
    It 'customer report renders with Microsoft 365 data only' {
        $T = Build-CippCustomerReportTree -Data @{ TenantName = 'X'; Period = $Period; M365 = $Data.M365; Atera = $null } -Findings @()
        $Bytes = ConvertTo-CippReportPdf -Blocks $T.Blocks -Variables $T.Variables -TenantName 'X' -ReportName 'T'
        [Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }
    It 'pre-check renders and orders held companies first' {
        $T = Build-CippReportPrecheckTree -Period $Period -Companies @(
            @{ TenantName = 'Ready Co'; Findings = @() }
            @{ TenantName = 'Held Co'; Findings = @([pscustomobject]@{ Severity = 'Block'; Area = 'Data'; Title = 'x'; Detail = 'y'; Items = @(); Count = 0; Customer = $null }) }
        )
        ($T.Blocks | Where-Object { $_.type -eq 'page' -or $_.Type -eq 'page' } | Select-Object -Skip 1 -First 1 | ConvertTo-Json -Depth 5) | Should -Match 'Held Co'
        $Bytes = ConvertTo-CippReportPdf -Blocks $T.Blocks -Variables $T.Variables -TenantName 'MSP' -ReportName 'T'
        [Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }
}

Describe 'Report sections' {
    BeforeAll {
        $script:Data = Get-CIPPCustomerReportData -TenantFilter 'contoso.com' -Period $Period -Now $Now
        $script:F = Get-CIPPReportFindings -Data $Data -AteraEnabled $true
    }
    It 'normalises stored, posted and plain section lists (order kept, duplicates dropped)' {
        ConvertFrom-CIPPReportSectionList '["devices","summary","devices"]' | Should -Be @('devices', 'summary')
        ConvertFrom-CIPPReportSectionList @(@{ label = 'S'; value = 'summary' }, [pscustomobject]@{ label = 'D'; value = 'devices' }) | Should -Be @('summary', 'devices')
        @(ConvertFrom-CIPPReportSectionList '').Count | Should -Be 0
        @(ConvertFrom-CIPPReportSectionList $null).Count | Should -Be 0
    }
    It 'builds only the chosen sections, in the chosen order' {
        $T = Build-CippCustomerReportTree -Data $Data -Findings $F -Sections @('devices', 'summary')
        & $PageTitles $T.Blocks | Should -Be @('Devices', 'Summary')
    }
    It 'builds every built-in section when no list is given' {
        $T = Build-CippCustomerReportTree -Data $Data -Findings $F
        (& $PageTitles $T.Blocks)[0] | Should -Be 'Summary'
        (& $PageTitles $T.Blocks)[-1] | Should -Be 'Recommendations'
    }
    It 'adds a Report Builder section as its own page and still renders a PDF' {
        $Extra = @{ 'template:abc-1' = @{ Title = 'Board pack'; Blocks = @(@{ type = 'blank'; title = 'Board notes'; content = '<p>Quarterly</p>' }) } }
        $T = Build-CippCustomerReportTree -Data $Data -Findings $F -Sections @('summary', 'template:abc-1', 'template:unknown') -ExtraSections $Extra
        & $PageTitles $T.Blocks | Should -Be @('Summary', 'Board pack')
        $Bytes = ConvertTo-CippReportPdf -Blocks $T.Blocks -Variables $T.Variables -TenantName 'Contoso' -ReportName 'T'
        [Text.Encoding]::ASCII.GetString($Bytes[0..4]) | Should -Be '%PDF-'
    }
    It 'uses the company list, then the default list, then all built-ins' {
        (Resolve-CIPPReportSections -TenantFilter 'contoso.com' -CompanySections '["support"]' -DefaultSections @('devices')).Source | Should -Be 'Company'
        $D = Resolve-CIPPReportSections -TenantFilter 'contoso.com' -CompanySections '' -DefaultSections @('devices')
        $D.Source | Should -Be 'Default'
        $D.Sections | Should -Be @('devices')
        $B = Resolve-CIPPReportSections -TenantFilter 'contoso.com'
        $B.Source | Should -Be 'BuiltIn'
        $B.Sections.Count | Should -Be 7
    }
    It 'loads Report Builder templates for the tenant and reports deleted ones' {
        Mock Get-CIPPAzDataTableEntity { if ($Filter -match "RowKey eq 'abc-1'") { $script:TemplateRow } }
        $R = Resolve-CIPPReportSections -TenantFilter 'contoso.com' -CompanySections '["template:abc-1","template:gone-2","summary"]'
        $R.ExtraSections['template:abc-1'].Title | Should -Be 'Board pack'
        $R.ExtraSections['template:abc-1'].Blocks[0].content | Should -Match 'for contoso.com'
        $R.ExtraSections.ContainsKey('template:gone-2') | Should -BeFalse
        $R.Missing[0] | Should -Match 'gone-2'
    }
}

Describe 'Invoke-CIPPReportGeneration' {
    BeforeEach {
        $script:Stored = @{}
        $script:Mails = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:Stored[$TableName] = $Entity }
        Mock Send-CIPPAlert { $script:Mails.Add([pscustomobject]@{ To = $altEmail; Title = $Title; Html = $HTMLContent; Attachments = $Attachments }) }
        Mock Get-CIPPReportPeriod { $script:Period } -ParameterFilter { $Period -eq 'LastMonth' }
    }

    It 'stores the PDF where Generated Reports reads it and records the run' {
        $R = Invoke-CIPPReportGeneration -TenantFilter 'contoso.com' -ReportType Customer -Test
        $Stored['ReportBuilderReports'].PartitionKey | Should -Be 'contoso.com'
        $Stored['ReportBuilderReports'].TemplateName | Should -Match 'TEST'
        $Stored['ReportBuilderPdfs'].RowKey | Should -Be $R.ReportGUID
        [Convert]::FromBase64String($Stored['ReportBuilderPdfs'].Pdf)[0..4] | ForEach-Object { [char]$_ } | Join-String | Should -Be '%PDF-'
        $Stored['ReportRuns'].IsTest | Should -BeTrue
        $Mails.Count | Should -Be 0
    }

    It 'emails each typed address once, as a TEST, with the PDF attached' {
        $null = Invoke-CIPPReportGeneration -TenantFilter 'contoso.com' -ReportType Customer -Test -SendTo 'a@msp.com; b@msp.com'
        @($Mails.To) | Should -Be @('a@msp.com', 'b@msp.com')
        $Mails[0].Title | Should -Match 'TEST'
        $Mails[0].Html | Should -Match 'TEST'
        $Mails[0].Attachments[0].ContentType | Should -Be 'application/pdf'
    }

    It 'builds the company''s chosen sections, including a Report Builder template' {
        Mock Get-CIPPAzDataTableEntity {
            if ($TableName -eq 'ReportCompanies') { [pscustomobject]@{ RowKey = 't1'; Sections = '["template:abc-1","summary","template:gone-2"]' } }
            elseif ($TableName -eq 'templates' -and $Filter -match "RowKey eq 'abc-1'") { $script:TemplateRow }
        }
        $R = Invoke-CIPPReportGeneration -TenantFilter 'contoso.com' -ReportType Customer -Test
        $Blocks = $Stored['ReportBuilderReports'].Blocks | ConvertFrom-Json
        & $PageTitles $Blocks | Should -Be @('Board pack', 'Summary')
        $Stored['ReportBuilderReports'].Blocks | Should -Match 'Quarterly board notes'
        $Stored['ReportRuns'].Sections | Should -Be '["template:abc-1","summary","template:gone-2"]'
        $R.Results | Should -Match 'Skipped Report Builder section.*gone-2'
    }

    It 'generates a pre-check' {
        $R = Invoke-CIPPReportGeneration -TenantFilter 'contoso.com' -ReportType Precheck -Test
        $Stored['ReportBuilderReports'].TemplateName | Should -Match 'Pre-check'
        $Stored['ReportRuns'].Fix | Should -BeGreaterThan 0
    }
}
