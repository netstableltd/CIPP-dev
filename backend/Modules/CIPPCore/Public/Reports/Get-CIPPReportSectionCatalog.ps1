function Get-CIPPReportSectionCatalog {
    <#
    .SYNOPSIS
        Lists the sections a company's main report can be assembled from.

    .DESCRIPTION
        Two kinds of section:
          - Built-in sections of the monthly customer report (ids like 'devices').
          - Report Builder templates (ids 'template:<GUID>'): any template saved in the Report
            Builder, filled with the company's data when the report is generated.

        Returned in autocomplete shape (label/value) plus source and description, so the UI can use
        the list directly.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$BuiltInOnly)

    # In the default report order. 'm365-baseline' is opt-in: it is not in the default list.
    $BuiltIn = @(
        [pscustomobject]@{ value = 'summary'; label = 'Summary'; source = 'Built-in'; description = 'Headline figures, overall status and the optional note from your team.' }
        [pscustomobject]@{ value = 'devices'; label = 'Your computers (Atera)'; source = 'Built-in'; description = 'Every computer with its user, Windows version, hardware, last seen and status, and why any need attention.' }
        [pscustomobject]@{ value = 'updates'; label = 'Windows updates (Atera)'; source = 'Built-in'; description = 'Which computers are up to date or behind, Windows versions and when their security updates end.' }
        [pscustomobject]@{ value = 'device-health'; label = 'Computer health (Atera)'; source = 'Built-in'; description = 'Alerts by computer, regularly overloaded machines, weak or ageing hardware, low disk space, Windows Home.' }
        [pscustomobject]@{ value = 'monitoring'; label = 'Monitoring alerts (Atera)'; source = 'Built-in'; description = 'Alerts raised in the period by severity and the most common alerts.' }
        [pscustomobject]@{ value = 'support'; label = 'Support requests (Atera)'; source = 'Built-in'; description = 'Requests opened and resolved, who raised them, time spent, and the list of requests.' }
        [pscustomobject]@{ value = 'purchases'; label = 'Purchases (Atera)'; source = 'Built-in'; description = 'Equipment and services bought this month and over the last 12 months, from Atera invoices.' }
        [pscustomobject]@{ value = 'm365-security'; label = 'Microsoft 365 security'; source = 'Built-in'; description = 'Secure Score with trend, and MFA coverage.' }
        [pscustomobject]@{ value = 'users-licences'; label = 'Users & licences'; source = 'Built-in'; description = 'User counts and the licence table with spare seats.' }
        [pscustomobject]@{ value = 'email'; label = 'Email & domains'; source = 'Built-in'; description = 'Fullest mailboxes, and SPF, DKIM and DMARC for each domain.' }
        [pscustomobject]@{ value = 'm365-baseline'; label = 'Microsoft 365 baseline (Executive Summary)'; source = 'Built-in'; description = 'CIPP''s full Executive Summary: standards, Secure Score, licences, devices, Conditional Access. Good for a first report or quarterly.' }
        [pscustomobject]@{ value = 'recommendations'; label = 'Recommendations'; source = 'Built-in'; description = 'What to do now, and what to plan for, from the pre-check.' }
    )
    if ($BuiltInOnly) { return $BuiltIn }

    $Templates = @()
    try {
        $Table = Get-CIPPTable -TableName 'templates'
        $Templates = foreach ($Row in @(Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ReportBuilderTemplate'")) {
            $Name = $null
            try { $Name = ($Row.JSON | ConvertFrom-Json -ErrorAction Stop).Name } catch {}
            if (-not $Name) { $Name = $Row.RowKey }
            [pscustomobject]@{ value = "template:$($Row.RowKey)"; label = "$Name (Report Builder)"; source = 'Report Builder'; description = 'A Report Builder template, filled with the company''s data.' }
        }
    } catch {
        Write-Information "Could not list Report Builder templates: $($_.Exception.Message)"
    }

    return @($BuiltIn) + @($Templates | Sort-Object label)
}
