function Get-CIPPReportBaselineSection {
    <#
    .SYNOPSIS
        Builds the "Microsoft 365 baseline" report section: CIPP's Executive Summary for the tenant.

    .DESCRIPTION
        The Executive Summary (Dashboard > Executive Summary PDF) is a full snapshot of the tenant's
        Microsoft 365 set-up: environment overview, security standards, Secure Score with comparisons,
        licences, Intune devices and Conditional Access. As a section of the monthly report it gives a
        customer the complete picture - useful as a first report, or quarterly.

        Uses the same data and layout as the Executive Summary (Get-CippExecutiveReportData and
        Build-CippExecutiveReportTree), without its photo pages. The first page is retitled
        'Microsoft 365 Baseline' so it reads as part of the monthly report.

    .PARAMETER TenantFilter
        Tenant default domain.

    .PARAMETER TenantName
        Name shown in the section.

    .OUTPUTS
        @{ Blocks } - empty when there is no cached data.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TenantFilter,
        [string]$TenantName
    )

    try {
        $Data = Get-CippExecutiveReportData -TenantFilter $TenantFilter -TenantName $TenantName
        $Tree = Build-CippExecutiveReportTree -Data $Data -SectionConfig @{ infographics = $false }
        $Blocks = @($Tree.Blocks | Where-Object { $_ -and "$($_.type)" -notin @('cover', 'hero') })
        $First = $Blocks | Where-Object { "$($_.type)" -eq 'page' } | Select-Object -First 1
        if ($First) { $First.title = 'Microsoft 365 Baseline' }
        return @{ Blocks = $Blocks }
    } catch {
        Write-Information "Microsoft 365 baseline unavailable for $TenantFilter - $($_.Exception.Message)"
        return @{ Blocks = @() }
    }
}
