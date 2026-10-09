function Get-CIPPReportCompanies {
    <#
    .SYNOPSIS
        Returns one row per CIPP tenant with its Reports settings, effective values and data status.

    .DESCRIPTION
        A "company" in the Reports area is a CIPP tenant. Per-company settings live in the
        ReportCompanies table (PartitionKey 'Company', RowKey = tenant customerId). Tenants with no
        row yet get defaults (reporting off, everything else "Default"), so every tenant is listed.

        Effective* properties resolve "Default" against the global settings (Get-CIPPReportSettings)
        so the UI and the scheduler read the same answer.

    .PARAMETER TenantId
        Optional customerId or default domain to return a single company.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [string]$TenantId
    )

    $Global = Get-CIPPReportSettings
    $Table = Get-CIPPTable -TableName 'ReportCompanies'
    $Rows = @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Company'")
    $Settings = @{}
    foreach ($Row in $Rows) { $Settings[$Row.RowKey] = $Row }

    $Mappings = @{}
    try {
        foreach ($Mapping in @(Get-ExtensionMapping -Extension 'Atera')) { $Mappings[$Mapping.RowKey] = $Mapping }
    } catch {
        Write-Information "Could not read Atera mappings: $($_.Exception.Message)"
    }

    # Section labels for the picker (built-ins + Report Builder templates). A section whose template
    # has been deleted keeps its id and is labelled as missing, so the user can see and remove it.
    $SectionLabels = @{}
    foreach ($Section in @(Get-CIPPReportSectionCatalog)) { $SectionLabels[$Section.value] = $Section.label }
    $ToSectionOption = { param($Id) [pscustomobject]@{ label = $(if ($SectionLabels[$Id]) { $SectionLabels[$Id] } else { "$Id (missing)" }); value = $Id } }
    $DefaultSectionNames = if (@($Global.DefaultSections).Count -gt 0) { (@($Global.DefaultSections) | ForEach-Object { (& $ToSectionOption $_).label }) -join ', ' } else { 'All built-in sections' }

    $Tenants = @(Get-Tenants -IncludeErrors)
    if ($TenantId) {
        $Tenants = @($Tenants | Where-Object { $_.customerId -eq $TenantId -or $_.defaultDomainName -eq $TenantId })
    }

    foreach ($Tenant in ($Tenants | Sort-Object displayName)) {
        $Row = $Settings[$Tenant.customerId]
        $Get = { param($Name, $Default) if ($Row -and $null -ne $Row.$Name -and "$($Row.$Name)" -ne '') { $Row.$Name } else { $Default } }

        $Enabled = [System.Convert]::ToBoolean((& $Get 'Enabled' $false))
        $DeliveryMode = & $Get 'DeliveryMode' 'Default'
        $ScheduleMode = & $Get 'ScheduleMode' 'Default'
        $PrecheckRecipients = & $Get 'PrecheckRecipients' ''
        $Mapping = $Mappings[$Tenant.customerId]
        $SectionIds = @(ConvertFrom-CIPPReportSectionList (& $Get 'Sections' ''))
        $Sections = @($SectionIds | ForEach-Object { & $ToSectionOption $_ })

        $DataIssues = [System.Collections.Generic.List[string]]::new()
        if ($Tenant.LastGraphError) { $DataIssues.Add('Microsoft 365 connection error') }
        if ($Mappings.Count -gt 0 -and -not $Mapping) { $DataIssues.Add('No Atera mapping') }

        [PSCustomObject]@{
            TenantId                    = $Tenant.customerId
            Tenant                      = $Tenant.defaultDomainName
            defaultDomainName           = $Tenant.defaultDomainName
            displayName                 = $Tenant.displayName
            Enabled                     = $Enabled
            Recipients                  = & $Get 'Recipients' ''
            PrecheckRecipients          = $PrecheckRecipients
            DeliveryMode                = $DeliveryMode
            ScheduleMode                = $ScheduleMode
            ReportDay                   = $(if ([int](& $Get 'ReportDay' 0) -gt 0) { "$([int](& $Get 'ReportDay' 0))" } else { '' })
            PausedUntil                 = & $Get 'PausedUntil' ''
            Notes                       = & $Get 'Notes' ''
            Sections                    = $Sections
            SectionsSummary             = if ($Sections.Count -gt 0) { ($Sections.label -join ', ') } else { "Default ($DefaultSectionNames)" }
            EffectiveDeliveryMode       = if ($DeliveryMode -eq 'Default') { $Global.DefaultDeliveryMode } else { $DeliveryMode }
            EffectivePrecheckRecipients = if ($PrecheckRecipients) { $PrecheckRecipients } else { $Global.PrecheckRecipients }
            AteraCustomerId             = if ($Mapping) { $Mapping.IntegrationId } else { '' }
            AteraCustomer               = if ($Mapping) { $Mapping.IntegrationName } else { '' }
            DataStatus                  = if ($DataIssues.Count -gt 0) { $DataIssues -join '; ' } else { 'OK' }
            LastModifiedBy              = & $Get 'ModifiedBy' ''
        }
    }
}
