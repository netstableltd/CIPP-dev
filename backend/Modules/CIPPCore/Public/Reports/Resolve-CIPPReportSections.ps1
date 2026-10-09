function Resolve-CIPPReportSections {
    <#
    .SYNOPSIS
        Works out which sections a company's main report contains, and loads any Report Builder templates among them.

    .DESCRIPTION
        Order of precedence for the section list:
          1. The company's own list (Reports > Companies > Edit > Report sections).
          2. The default list (Reports > Settings > Default report sections).
          3. All built-in sections.

        Report Builder sections ('template:<GUID>') are read from the templates table and their
        blocks filled with the tenant's data (Resolve-CippReportBuilderBlocks), exactly as the
        Report Builder does when generating a report. A template that has been deleted, or fails
        to load, is skipped and reported in Missing so the generator can log it.

    .OUTPUTS
        @{ Sections = [string[]]; ExtraSections = @{ id = @{ Title; Subtitle; Blocks } }; Missing = [string[]]; Source = 'Company'|'Default'|'BuiltIn' }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        $CompanySections,
        $DefaultSections,
        # The report period, so a template's 'period' date range means this report's month.
        $Period
    )

    $Company = @(ConvertFrom-CIPPReportSectionList $CompanySections)
    $Default = @(ConvertFrom-CIPPReportSectionList $DefaultSections)
    if ($Company.Count -gt 0) { $Sections = $Company; $Source = 'Company' }
    elseif ($Default.Count -gt 0) { $Sections = $Default; $Source = 'Default' }
    else { $Sections = @((Get-CIPPReportSectionCatalog -BuiltInOnly).value); $Source = 'BuiltIn' }

    $Extra = @{}
    $Missing = [System.Collections.Generic.List[string]]::new()
    $TemplateIds = @($Sections | Where-Object { $_ -like 'template:*' })
    if ($TemplateIds.Count -gt 0) {
        $Table = Get-CIPPTable -TableName 'templates'
        foreach ($Id in $TemplateIds) {
            $Guid = $Id.Substring('template:'.Length)
            try {
                if ($Guid -notmatch '^[A-Za-z0-9-]{1,64}$') { throw 'invalid template id' }
                $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$Guid'"
                if (-not $Row -or -not $Row.JSON) { throw 'template not found (it may have been deleted)' }
                $Template = $Row.JSON | ConvertFrom-Json -ErrorAction Stop
                $Blocks = @(Resolve-CippReportBuilderBlocks -Blocks @($Template.Blocks) -TenantFilter $TenantFilter -Period $Period)
                $Extra[$Id] = @{
                    Title    = $(if ($Template.Name) { [string]$Template.Name } else { 'Report Builder section' })
                    Subtitle = $null
                    Blocks   = $Blocks
                }
            } catch {
                $Missing.Add("$Id ($($_.Exception.Message))")
            }
        }
    }

    return @{
        Sections      = @($Sections)
        ExtraSections = $Extra
        Missing       = @($Missing)
        Source        = $Source
    }
}
