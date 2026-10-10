function Invoke-CIPPReportGeneration {
    <#
    .SYNOPSIS
        Generates a customer report or pre-check for one company, stores it, and optionally emails it.

    .DESCRIPTION
        1. Gathers data (Get-CIPPCustomerReportData) and runs the pre-check rules (Get-CIPPReportFindings).
        2. Builds the tree (customer report or pre-check) and renders a branded PDF.
        3. Stores the PDF in ReportBuilderReports / ReportBuilderPdfs, so it appears under
           Report Builder > Generated Reports and can be opened from there.
        4. Records the run in the ReportRuns table (history, schedule bookkeeping).
        5. Emails the PDF to -SendTo, one message per address.

        Safety: -SendTo is the only place mail goes. Test runs are always marked "TEST" and only
        ever reach the addresses typed in. Customer recipients from the company settings are only
        used by the scheduled path, which separately checks the "Allow sending to customers" switch.

    .PARAMETER TenantFilter
        Tenant default domain or customer id.

    .PARAMETER ReportType
        Customer or Precheck.

    .PARAMETER Period
        LastMonth (default), ThisMonth or yyyy-MM.

    .PARAMETER SendTo
        Addresses to email (comma/semicolon separated). Blank = generate and store only.

    .PARAMETER Test
        Marks the report and email as a test.

    .PARAMETER Summary
        Optional note shown on the first page of a customer report.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [ValidateSet('Customer', 'Precheck')][string]$ReportType = 'Customer',
        [string]$Period = 'LastMonth',
        [string]$SendTo,
        [switch]$Test,
        [string]$Summary,
        [string]$RequestedBy = 'CIPP',
        $Headers
    )

    $Tenant = Get-Tenants -IncludeErrors | Where-Object { $_.defaultDomainName -eq $TenantFilter -or $_.customerId -eq $TenantFilter } | Select-Object -First 1
    if (-not $Tenant) { throw "Unknown tenant '$TenantFilter'." }
    $Domain = $Tenant.defaultDomainName

    $Settings = Get-CIPPReportSettings
    $PeriodInfo = Get-CIPPReportPeriod -Period $Period
    $Data = Get-CIPPCustomerReportData -TenantFilter $Domain -Period $PeriodInfo
    # Breach lookup (live, with CIPP's cached results as a fallback) - only for tenants CIPP can read.
    $Data.Breaches = $null
    if ($Data.M365) {
        $BreachUsers = @(try { New-CIPPDbRequest -TenantFilter $Domain -Type 'Users' } catch { @() })
        $SharedUpns = @(try { New-CIPPDbRequest -TenantFilter $Domain -Type 'Mailboxes' | Where-Object { "$($_.recipientTypeDetails)" -match 'Shared|Room|Equipment|Scheduling|Discovery' } | ForEach-Object { "$($_.UPN)" } } catch { @() })
        $Data.Breaches = Get-CIPPReportBreachData -TenantFilter $Domain -Users $BreachUsers -SharedUpns $SharedUpns
    }

    $AteraEnabled = $false
    try {
        $ExtTable = Get-CIPPTable -TableName Extensionsconfig
        $ExtConfig = (Get-CIPPAzDataTableEntity @ExtTable).config | ConvertFrom-Json -ErrorAction Stop
        $AteraEnabled = [bool]$ExtConfig.Atera.Enabled
    } catch {}
    $Findings = @(Get-CIPPReportFindings -Data $Data -AteraEnabled $AteraEnabled)

    $SectionPlan = $null
    if ($ReportType -eq 'Customer') {
        # Sections: the company's own list, else the default list, else all built-ins.
        $CompanySections = $null
        try {
            $CompanyTable = Get-CIPPTable -TableName 'ReportCompanies'
            $CompanySections = (Get-CIPPAzDataTableEntity @CompanyTable -Filter "PartitionKey eq 'Company' and RowKey eq '$($Tenant.customerId)'").Sections
        } catch {}
        $SectionPlan = Resolve-CIPPReportSections -TenantFilter $Domain -CompanySections $CompanySections -DefaultSections $Settings.DefaultSections -Period $PeriodInfo
        $Baseline = $null
        if ($SectionPlan.Sections -contains 'm365-baseline') { $Baseline = Get-CIPPReportBaselineSection -TenantFilter $Domain -TenantName $Data.TenantName }
        $Tree = Build-CippCustomerReportTree -Data $Data -Findings $Findings -Summary $Summary -Sections $SectionPlan.Sections -ExtraSections $SectionPlan.ExtraSections -Baseline $Baseline
        $ReportName = 'Monthly IT Report'
        $PresetKey = 'customerReport'
    } else {
        $Tree = Build-CippReportPrecheckTree -Companies @(@{ TenantName = $Data.TenantName; TenantFilter = $Domain; Findings = $Findings }) -Period $PeriodInfo
        $ReportName = 'Report Pre-check'
        $PresetKey = 'reportPrecheck'
    }
    if ($Test) {
        $Tree.Variables.coverlabel = "$($Tree.Variables.coverlabel) $([char]0x2014) TEST"
        $Tree.Variables.coverfooternote = 'TEST REPORT - sent for checking only'
    }

    $PresetId = $null
    try { $PresetId = [string](Get-CIPPBrandingSettings).reportDefaults.$PresetKey } catch {}

    # Date on the cover in the reports time zone, UK style.
    $LocalNow = (Get-Date).ToUniversalTime()
    try { $LocalNow = [System.TimeZoneInfo]::ConvertTimeFromUtc($LocalNow, [System.TimeZoneInfo]::FindSystemTimeZoneById($Settings.TimeZone)) } catch {}
    $GeneratedOn = $LocalNow.ToString('d MMMM yyyy', [cultureinfo]::GetCultureInfo('en-GB'))

    $Bytes = ConvertTo-CippReportPdf -Blocks $Tree.Blocks -Variables $Tree.Variables -TenantName $Data.TenantName -TenantFilter $Domain -ReportName $ReportName -BrandingPresetId $PresetId -GeneratedOn $GeneratedOn
    $SafeName = ($Data.TenantName -replace '[^\w\- ]', '').Trim() -replace '\s+', '-'
    $FileName = "$SafeName-$($ReportName -replace '\s+', '-')-$($PeriodInfo.Key)$(if ($Test) { '-TEST' }).pdf"
    $Base64 = [Convert]::ToBase64String($Bytes)

    # -- Store so it shows in Generated Reports --------------------------------------------
    $ReportGUID = [string](New-Guid).Guid
    $TemplateName = "$ReportName $([char]0x2014) $($PeriodInfo.Label)$(if ($Test) { ' (TEST)' })"
    $ReportTable = Get-CIPPTable -TableName 'ReportBuilderReports'
    Add-CIPPAzDataTableEntity @ReportTable -Force -Entity @{
        PartitionKey = $Domain
        RowKey       = $ReportGUID
        TemplateName = [string]$TemplateName
        TenantFilter = [string]$Domain
        Blocks       = [string](ConvertTo-Json -InputObject @($Tree.Blocks) -Depth 20 -Compress)
        GeneratedAt  = [string](Get-Date).ToUniversalTime().ToString('o')
        Status       = 'Completed'
        Settings     = [string](ConvertTo-Json -InputObject @{ brandingPresetId = $PresetId; size = 'A4'; orientation = 'portrait'; source = 'Reports'; reportType = $ReportType } -Compress)
    }
    $PdfTable = Get-CIPPTable -TableName 'ReportBuilderPdfs'
    Add-CIPPAzDataTableEntity @PdfTable -Force -Entity @{
        PartitionKey = $Domain
        RowKey       = $ReportGUID
        FileName     = $FileName
        Pdf          = $Base64
    }

    $Link = $null
    try {
        $ConfigTable = Get-CIPPTable -TableName Config
        $Url = (Get-CIPPAzDataTableEntity @ConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'").Value
        if ($Url) { $Link = "https://$Url/tools/report-builder/view?id=$ReportGUID" }
    } catch {}

    # -- Email ---------------------------------------------------------------------------------
    $Recipients = @("$SendTo" -split '[,;\s]+' | Where-Object { $_ })
    $Sent = [System.Collections.Generic.List[string]]::new()
    $SendErrors = [System.Collections.Generic.List[string]]::new()
    if ($Recipients.Count -gt 0) {
        $Subject = "$($Data.TenantName) $([char]0x2014) $ReportName $([char]0x2014) $($PeriodInfo.Label)$(if ($Test) { ' (TEST)' })"
        $Intro = if ($ReportType -eq 'Customer') {
            "Please find attached the monthly IT report for $([System.Net.WebUtility]::HtmlEncode($Data.TenantName)) covering $($PeriodInfo.Label)."
        } else {
            "Attached is the pre-check for $([System.Net.WebUtility]::HtmlEncode($Data.TenantName)) ahead of the $($PeriodInfo.Label) report: $(@($Findings | Where-Object Severity -EQ 'Block').Count) block, $(@($Findings | Where-Object Severity -EQ 'Fix').Count) fix and $(@($Findings | Where-Object Severity -EQ 'Info').Count) info item(s)."
        }
        $TestBanner = if ($Test) { '<p style="padding:8px;background:#FFF4E5;border-left:4px solid #744210"><b>TEST</b> - this report was generated on request and sent only to you. It has not been sent to the customer.</p>' } else { '' }
        $LinkHtml = ''
        if ($Link) { $LinkHtml = '<p><a href="{0}">Open in CIPP</a></p>' -f $Link }
        $Html = $TestBanner + '<p>' + $Intro + '</p>' + $LinkHtml
        $Attachment = @(@{ Name = $FileName; ContentType = 'application/pdf'; ContentBytes = $Base64 })
        foreach ($Address in $Recipients) {
            try {
                $null = Send-CIPPAlert -Type 'email' -Title $Subject -HTMLContent $Html -TenantFilter $Domain -altEmail $Address -Attachments $Attachment -APIName 'Reports'
                $Sent.Add($Address)
            } catch {
                $SendErrors.Add("$Address ($($_.Exception.Message))")
            }
        }
    }

    # -- Run history ---------------------------------------------------------------------------
    try {
        $RunTable = Get-CIPPTable -TableName 'ReportRuns'
        Add-CIPPAzDataTableEntity @RunTable -Force -Entity @{
            PartitionKey = $PeriodInfo.Key
            RowKey       = $ReportGUID
            TenantId     = [string]$Tenant.customerId
            Tenant       = $Domain
            Company      = [string]$Data.TenantName
            ReportType   = $ReportType
            IsTest       = [bool]$Test
            SentTo       = ($Sent -join ', ')
            SendErrors   = ($SendErrors -join '; ')
            Block        = @($Findings | Where-Object Severity -EQ 'Block').Count
            Fix          = @($Findings | Where-Object Severity -EQ 'Fix').Count
            Info         = @($Findings | Where-Object Severity -EQ 'Info').Count
            FileName     = $FileName
            Sections     = $(if ($SectionPlan) { ConvertTo-Json -InputObject @($SectionPlan.Sections) -Compress } else { '' })
            RequestedBy  = [string]$RequestedBy
            GeneratedAt  = (Get-Date).ToUniversalTime().ToString('o')
        }
    } catch {
        Write-Information "Could not record report run: $($_.Exception.Message)"
    }

    $Message = "$TemplateName generated for $($Data.TenantName)"
    if ($Sent.Count -gt 0) { $Message += " and emailed to $($Sent -join ', ')" }
    if ($SendErrors.Count -gt 0) { $Message += ". Email failed for: $($SendErrors -join '; ')" }
    $Message += '.'
    if ($SectionPlan -and @($SectionPlan.Missing).Count -gt 0) { $Message += " Skipped Report Builder section(s): $(@($SectionPlan.Missing) -join '; ')." }
    if ($Link) { $Message += " Open it in CIPP: $Link" }
    Write-LogMessage -headers $Headers -API 'Reports' -tenant $Domain -tenantId $Tenant.customerId -message $Message -Sev $(if ($SendErrors.Count -gt 0) { 'Warning' } else { 'Info' })

    return [PSCustomObject]@{
        Results    = $Message
        ReportGUID = $ReportGUID
        Link       = $Link
        FileName   = $FileName
        Findings   = $Findings
        Sent       = @($Sent)
    }
}
