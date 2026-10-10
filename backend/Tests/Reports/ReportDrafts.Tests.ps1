# Pester tests for customer report drafts (Reports > Review).
#
# Pins: review changes alter only the customer's recommendations (hidden, reworded, affected list,
# added ones) and never the internal pre-check items; a draft is generated with its saved changes,
# replaces the previous draft PDF and resets approval; approve / reopen / discard / send follow the
# status rules; sending needs approval, the customer-send switch and recipients, and sends the
# approved PDF itself; a user without access to the tenant gets nothing.

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
    function Get-CIPPAzDataTableEntity { param($TableName, $Filter, $Property) }
    function Add-CIPPAzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-AzDataTableEntity { param($TableName, $Entity, [switch]$Force) }
    function Remove-CIPPAzDataTableEntity { param($TableName, $Entity) }
    function Write-LogMessage { param($headers, $API, $tenant, $tenantId, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function Get-Tenants { param([switch]$IncludeErrors) [pscustomobject]@{ customerId = '11111111-1111-1111-1111-111111111111'; displayName = 'Contoso Ltd'; defaultDomainName = 'contoso.com' } }
    function Invoke-CIPPReportGeneration { param($TenantFilter, $ReportType, $Period, [switch]$Draft, $Overrides, $RequestedBy, $Headers) }
    function Send-CIPPAlert { param($Type, $Title, $HTMLContent, $TenantFilter, $altEmail, $Attachments, $APIName) }
    function Get-CIPPReportSettings { [pscustomobject]@{ CustomerSendEnabled = $script:SendEnabled } }
    function Get-CIPPReportCompanies { param($TenantId) [pscustomobject]@{ TenantId = $TenantId; Recipients = $script:Recipients } }
    function Test-CIPPReportSectionId { param($Id) $Id -in @('summary', 'devices', 'breaches', 'recommendations') }
    $script:AllowedTenants = @('AllTenants')
    function Test-CIPPAccess { param($Request, [switch]$TenantList) $script:AllowedTenants }

    foreach ($Name in 'Test-CIPPReportAccess', 'Get-CIPPReportPeriod', 'Resolve-CIPPReportOverrides', 'New-CIPPReportDraft', 'Remove-CIPPReportStoredPdf', 'Send-CIPPReportDraft', 'Invoke-ExecReportDraft', 'Invoke-ListReportDrafts') {
        . (& $Find "$Name.ps1")
    }

    $script:Findings = @(
        [pscustomobject]@{ Id = 'devices-storage'; Severity = 'Fix'; Area = 'Device health'; Title = 'Drives over 75% full'; Detail = 'internal detail'; Customer = 'Free up space on the computer.'; CustomerItems = @('SERVER (D: 100% full)'); Items = @('SERVER (D: 100%)') }
        [pscustomobject]@{ Id = 'devices-home-edition'; Severity = 'Info'; Area = 'Device health'; Title = 'Windows Home'; Detail = 'x'; Customer = 'Upgrade to Pro.'; CustomerItems = @('CAD1'); Items = @('CAD1') }
        [pscustomobject]@{ Id = 'monitoring-silent'; Severity = 'Fix'; Area = 'Monitoring'; Title = 'No alerts in 90 days'; Detail = 'check profile'; Customer = $null; CustomerItems = @(); Items = @() }
    )
    $Principal = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes('{"userDetails":"dave@contoso.com"}'))
    function New-DraftRequest($Body) { [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ExecReportDraft' }; Headers = @{ 'x-ms-client-principal' = $Principal }; Body = [pscustomobject]$Body; Query = @{} } }
    $script:DraftId = '11111111-1111-1111-1111-111111111111_2026-09'
    function New-DraftRow([string]$Status = 'Draft') {
        [pscustomobject]@{ PartitionKey = 'Draft'; RowKey = $script:DraftId; TenantId = '11111111-1111-1111-1111-111111111111'; Tenant = 'contoso.com'; Company = 'Contoso Ltd'; PeriodKey = '2026-09'; PeriodLabel = 'September 2026'; Status = $Status; ReportGUID = '22222222-2222-2222-2222-222222222222'; FileName = 'Contoso.pdf'; Overrides = '{"Note":"Hello","HiddenFindings":["devices-home-edition"]}'; Findings = '[]'; Sections = '["summary"]'; Timestamp = 'x' }
    }
}

Describe 'Resolve-CIPPReportOverrides' {
    It 'hides, rewords and changes the affected list of customer recommendations only' {
        $O = @{ HiddenFindings = @('devices-home-edition', 'monitoring-silent'); FindingText = @{ 'devices-storage' = 'Please tidy the D: drive on SERVER.' }; FindingItems = @{ 'devices-storage' = 'SERVER, CAD1' } }
        $R = Resolve-CIPPReportOverrides -Findings $script:Findings -Overrides $O
        ($R | Where-Object Id -EQ 'devices-storage').Customer | Should -Be 'Please tidy the D: drive on SERVER.'
        @(($R | Where-Object Id -EQ 'devices-storage').CustomerItems) | Should -Be @('SERVER', 'CAD1')
        ($R | Where-Object Id -EQ 'devices-home-edition').Customer | Should -BeNullOrEmpty
        # Internal items stay as they were (still in the pre-check).
        ($R | Where-Object Id -EQ 'monitoring-silent').Detail | Should -Be 'check profile'
        # The originals are untouched.
        $script:Findings[0].Customer | Should -Be 'Free up space on the computer.'
    }

    It 'adds recommendations typed in review, as to do now or to plan for' {
        $R = Resolve-CIPPReportOverrides -Findings @() -Overrides @{ Extra = @(@{ text = 'Replace the office switch.'; plan = $true }, @{ text = '  ' }, @{ text = 'Change the Wi-Fi password.' }) }
        $R.Count | Should -Be 2
        $R[0].Severity | Should -Be 'Info'
        $R[0].Customer | Should -Be 'Replace the office switch.'
        $R[1].Severity | Should -Be 'Fix'
    }

    It 'leaves everything as it is without overrides' {
        $R = Resolve-CIPPReportOverrides -Findings $script:Findings -Overrides $null
        @($R.Customer | Where-Object { $_ }).Count | Should -Be 2
    }
}

Describe 'New-CIPPReportDraft' {
    BeforeEach {
        $script:Saved = $null
        $script:Generated = $null
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
        Mock Remove-CIPPReportStoredPdf {}
        Mock Invoke-CIPPReportGeneration {
            $script:Generated = @{ Draft = [bool]$Draft; Overrides = $Overrides; Period = $Period }
            [pscustomobject]@{ ReportGUID = '33333333-3333-3333-3333-333333333333'; FileName = 'Contoso.pdf'; TenantName = 'Contoso Ltd'; Findings = $script:Findings; Sections = @('summary', 'devices'); Link = 'x' }
        }
    }

    It 'generates a draft with the saved changes, replaces the old PDF and resets approval' {
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Approved' }
        $R = New-CIPPReportDraft -TenantFilter 'contoso.com' -Period '2026-09'
        $Generated.Draft | Should -BeTrue
        $Generated.Overrides.Note | Should -Be 'Hello'
        Should -Invoke Remove-CIPPReportStoredPdf -Times 1 -ParameterFilter { $ReportGUID -eq '22222222-2222-2222-2222-222222222222' }
        $Saved.RowKey | Should -Be $script:DraftId
        $Saved.Status | Should -Be 'Draft'
        $Saved.ApprovedBy | Should -Be ''
        $Saved.ReportGUID | Should -Be '33333333-3333-3333-3333-333333333333'
        @($Saved.Findings | ConvertFrom-Json).Count | Should -Be 3
        $R.RowKey | Should -Be $script:DraftId
    }

    It 'refuses to regenerate a report that has been sent' {
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Sent' }
        { New-CIPPReportDraft -TenantFilter 'contoso.com' -Period '2026-09' } | Should -Throw '*already been sent*'
        $Saved | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-ExecReportDraft' {
    BeforeEach {
        $script:Saved = $null
        $script:Removed = $false
        $script:SendEnabled = $true
        $script:Recipients = 'boss@contoso.com'
        $script:Mails = [System.Collections.Generic.List[object]]::new()
        Mock Add-CIPPAzDataTableEntity { $script:Saved = $Entity }
        Mock Remove-AzDataTableEntity { $script:Removed = $true }
        Mock Remove-CIPPReportStoredPdf {}
        Mock Send-CIPPAlert { $script:Mails.Add(@{ To = $altEmail; Attachments = $Attachments }) }
    }

    It 'approves a draft, recording who' {
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Draft' }
        $r = Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Approve'; Id = $script:DraftId })
        $r.StatusCode | Should -Be 200
        $Saved.Status | Should -Be 'Approved'
        $Saved.ApprovedBy | Should -Be 'dave@contoso.com'
        $Saved.ContainsKey('Timestamp') | Should -BeFalse
    }

    It 'will not approve a report twice' {
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Approved' }
        (Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Approve'; Id = $script:DraftId })).StatusCode | Should -Be 409
    }

    It 'sends the approved PDF itself to the company recipients and marks it sent' {
        Mock Get-CIPPAzDataTableEntity {
            if ($Filter -match "PartitionKey eq 'Draft'") { New-DraftRow 'Approved' } else { [pscustomobject]@{ RowKey = '22222222-2222-2222-2222-222222222222'; Pdf = 'UERGREFUQQ=='; FileName = 'Contoso.pdf' } }
        }
        $r = Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Send'; Id = $script:DraftId })
        $r.StatusCode | Should -Be 200
        $Mails.Count | Should -Be 1
        $Mails[0].To | Should -Be 'boss@contoso.com'
        $Mails[0].Attachments[0].ContentBytes | Should -Be 'UERGREFUQQ=='
        $Saved.Status | Should -Be 'Sent'
        $Saved.SentTo | Should -Be 'boss@contoso.com'
    }

    It 'does not send <Case>' -ForEach @(
        @{ Case = 'a draft that is not approved'; Status = 'Draft'; Enabled = $true; To = 'boss@contoso.com'; Message = '*Approve the draft*' }
        @{ Case = 'while sending to customers is off'; Status = 'Approved'; Enabled = $false; To = 'boss@contoso.com'; Message = '*switched off*' }
        @{ Case = 'when the company has no recipients'; Status = 'Approved'; Enabled = $true; To = ''; Message = '*no report recipients*' }
    ) {
        $script:SendEnabled = $Enabled
        $script:Recipients = $To
        $script:TestStatus = $Status
        Mock Get-CIPPAzDataTableEntity { New-DraftRow $script:TestStatus }
        $r = Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Send'; Id = $script:DraftId })
        $r.StatusCode | Should -Be 400
        $r.Body.Results | Should -BeLike $Message
        $Mails.Count | Should -Be 0
    }

    It 'discards a draft and its PDF, but never a sent report' {
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Draft' }
        (Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Discard'; Id = $script:DraftId })).StatusCode | Should -Be 200
        $Removed | Should -BeTrue
        Should -Invoke Remove-CIPPReportStoredPdf -Times 1
        $script:Removed = $false
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Sent' }
        (Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Discard'; Id = $script:DraftId })).StatusCode | Should -Be 409
        $Removed | Should -BeFalse
    }

    It 'rejects overrides with an unknown section' {
        $r = Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Generate'; TenantId = '11111111-1111-1111-1111-111111111111'; Period = '2026-09'; Overrides = [pscustomobject]@{ HiddenSections = @('nope') } })
        $r.StatusCode | Should -Be 400
    }

    It 'passes cleaned overrides to the draft' {
        Mock New-CIPPReportDraft { $script:Passed = $Overrides; [pscustomobject]@{ Results = 'ok'; RowKey = 'k'; ReportGUID = 'g' } }
        $O = [pscustomobject]@{ Note = ' Thanks for a good month '; HiddenSections = @('breaches'); HiddenFindings = @('devices-home-edition', 'bad id!'); FindingText = [pscustomobject]@{ 'devices-storage' = 'Tidy D:' }; Extra = @([pscustomobject]@{ text = 'New switch'; plan = $true }, [pscustomobject]@{ text = '' }) }
        $r = Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Generate'; TenantId = '11111111-1111-1111-1111-111111111111'; Period = '2026-09'; Overrides = $O })
        $r.StatusCode | Should -Be 200
        $Passed.Note | Should -Be 'Thanks for a good month'
        $Passed.HiddenSections | Should -Be @('breaches')
        $Passed.HiddenFindings | Should -Be @('devices-home-edition')
        $Passed.FindingText['devices-storage'] | Should -Be 'Tidy D:'
        @($Passed.Extra).Count | Should -Be 1
    }

    It 'treats a draft of another tenant as not found for a limited user' {
        $script:AllowedTenants = @('99999999-9999-9999-9999-999999999999')
        try {
            Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Draft' }
            (Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Approve'; Id = $script:DraftId })).StatusCode | Should -Be 404
            $Saved | Should -BeNullOrEmpty
            (Invoke-ExecReportDraft -Request (New-DraftRequest @{ Action = 'Generate'; TenantId = '11111111-1111-1111-1111-111111111111' })).StatusCode | Should -Be 403
        } finally { $script:AllowedTenants = @('AllTenants') }
    }
}

Describe 'Invoke-ListReportDrafts' {
    It 'lists drafts with counts, and one draft with its findings and changes' {
        Mock Get-CIPPAzDataTableEntity { New-DraftRow 'Draft' }
        $Req = [pscustomobject]@{ Params = @{ CIPPEndpoint = 'ListReportDrafts' }; Headers = @{}; Query = @{} }
        $r = Invoke-ListReportDrafts -Request $Req
        $r.StatusCode | Should -Be 200
        @($r.Body).Count | Should -Be 1
        @($r.Body)[0].Changes | Should -Be 2
        $Req.Query = @{ Id = $script:DraftId }
        $One = (Invoke-ListReportDrafts -Request $Req).Body
        $One.Overrides.Note | Should -Be 'Hello'
        @($One.Sections) | Should -Be @('summary')
    }
}
