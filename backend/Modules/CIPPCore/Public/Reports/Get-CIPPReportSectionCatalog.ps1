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

    $BuiltIn = @(
        [pscustomobject]@{ value = 'summary'; label = 'Summary'; source = 'Built-in'; description = 'Headline figures, overall status and the optional note from your team.' }
        [pscustomobject]@{ value = 'm365-security'; label = 'Microsoft 365 security'; source = 'Built-in'; description = 'Secure Score with trend, and MFA coverage.' }
        [pscustomobject]@{ value = 'users-licences'; label = 'Users & licences'; source = 'Built-in'; description = 'User counts and the licence table with spare seats.' }
        [pscustomobject]@{ value = 'devices'; label = 'Devices (Atera)'; source = 'Built-in'; description = 'Device count, operating systems and devices needing attention.' }
        [pscustomobject]@{ value = 'monitoring'; label = 'Monitoring alerts (Atera)'; source = 'Built-in'; description = 'Alerts raised in the period by severity and the most common alerts.' }
        [pscustomobject]@{ value = 'support'; label = 'Support requests (Atera)'; source = 'Built-in'; description = 'Requests opened and resolved, time spent, and the list of requests.' }
        [pscustomobject]@{ value = 'recommendations'; label = 'Recommendations'; source = 'Built-in'; description = 'Open pre-check items written for the customer.' }
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
