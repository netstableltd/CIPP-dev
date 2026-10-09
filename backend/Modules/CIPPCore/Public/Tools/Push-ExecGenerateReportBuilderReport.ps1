function Push-ExecGenerateReportBuilderReport {
    <#
    .FUNCTIONALITY
        Entrypoint
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [Alias('input')]
        $InputValue,
        $TenantFilter,
        $TemplateName,
        $Blocks,
        $TemplateGUID,
        $IncludeRawAttachments,
        $Settings,
        # Render and return the PDF without persisting a generated-report row - powers the builder's
        # live preview/download from the current unsaved state.
        [switch]$PreviewOnly
    )

    try {
        if ([string]::IsNullOrEmpty($TenantFilter)) {
            throw 'TenantFilter is required'
        }

        # Page setup and branding for this report: page size, orientation, cover, footer,
        # watermark and which branding preset to render against.
        $ParsedSettings = $null
        if ($Settings) {
            if ($Settings -is [string]) {
                try { $ParsedSettings = ConvertFrom-Json -InputObject $Settings } catch { $ParsedSettings = $null }
            } else {
                $ParsedSettings = $Settings
            }
        }

        # Parse Blocks
        $ParsedBlocks = @()
        if ($Blocks) {
            if ($Blocks -is [string]) {
                $ParsedBlocks = @(ConvertFrom-Json -InputObject $Blocks)
            } else {
                $ParsedBlocks = @($Blocks)
            }
        } elseif ($TemplateGUID) {
            # A schedule that references a template by GUID follows the template: blocks, page
            # setup and name are read fresh on every run, so edits made to the template after the
            # schedule was created are picked up without recreating the schedule.
            $TemplateTable = Get-CippTable -tablename 'templates'
            $Template = Get-CIPPAzDataTableEntity @TemplateTable -Filter "PartitionKey eq 'ReportBuilderTemplate' and RowKey eq '$($TemplateGUID)'"
            if (-not $Template -or -not $Template.JSON) {
                throw "Report template $TemplateGUID was not found. It may have been deleted; recreate the schedule from a saved template."
            }
            $TemplateData = ConvertFrom-Json -InputObject $Template.JSON
            $ParsedBlocks = @($TemplateData.Blocks)
            if ($TemplateData.Name) {
                $TemplateName = $TemplateData.Name
            }
            # A schedule created before page setup existed passes no Settings, so fall back to
            # whatever the template itself was saved with.
            if (-not $ParsedSettings -and $TemplateData.Settings) {
                $ParsedSettings = $TemplateData.Settings
            }
        }

        if ($ParsedBlocks.Count -eq 0) {
            throw 'No blocks provided and no template found'
        }

        $EnrichedBlocks = @(Resolve-CippReportBuilderBlocks -Blocks $ParsedBlocks -TenantFilter $TenantFilter)

        # -- Render the PDF server-side via the shared CIPPSharp component kit --
        # A render failure must not lose the report: the enriched blocks are still stored so the report
        # exists and can be re-rendered, and the failure is logged rather than thrown.
        $PdfBytes = $null
        try {
            # The tenant's name for the cover, as the branding names it (alias, organisation name or
            # domain). The template's chosen preset wins, else the global branding settings - the same
            # resolution ConvertTo-CippReportPdf applies to the rest of the branding.
            $TenantDisplayName = Get-CippReportTenantName -TenantFilter $TenantFilter -BrandingPresetId ([string]$ParsedSettings.brandingPresetId)
            $PageSizePref = if ($ParsedSettings -and $ParsedSettings.size) { [string]$ParsedSettings.size } else { 'A4' }
            $IsLandscape = ($ParsedSettings -and "$($ParsedSettings.orientation)" -eq 'landscape')

            $PdfBytes = ConvertTo-CippReportPdf -Blocks $EnrichedBlocks -BrandingPresetId ([string]$ParsedSettings.brandingPresetId) `
                -TenantName $TenantDisplayName -TenantFilter $TenantFilter -ReportName ($TemplateName ?? 'Report') `
                -PageSize $PageSizePref -Landscape:$IsLandscape
        } catch {
            $PdfError = Get-CippException -Exception $_
            Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "PDF render failed, storing report without a PDF: $($PdfError.NormalizedError)" -Sev 'Warning' -LogData $PdfError
        }

        # Preview: hand the freshly rendered bytes straight back without persisting a report row.
        if ($PreviewOnly) {
            return @{ PdfBytes = $PdfBytes }
        }
        $PdfBase64 = if ($PdfBytes) { [Convert]::ToBase64String($PdfBytes) } else { '' }
        $PdfFileName = ("$($TemplateName ?? 'Report')_$TenantFilter" -replace '[^a-zA-Z0-9_\-]', '_') + '.pdf'

        # Store the generated report
        $ReportGUID = (New-Guid).GUID
        $ReportTable = Get-CippTable -tablename 'ReportBuilderReports'
        $ReportEntity = @{
            PartitionKey   = $TenantFilter
            RowKey         = [string]$ReportGUID
            TemplateName   = [string]($TemplateName ?? 'Scheduled Report')
            TenantFilter   = [string]$TenantFilter
            Blocks         = [string](ConvertTo-Json -InputObject @($EnrichedBlocks) -Depth 20 -Compress)
            GeneratedAt    = [string](Get-Date).ToString('o')
            Status         = 'Completed'
            Settings       = if ($ParsedSettings) { [string](ConvertTo-Json -InputObject $ParsedSettings -Depth 10 -Compress) } else { '' }
        }
        Add-CIPPAzDataTableEntity @ReportTable -Entity $ReportEntity -Force

        # The finished PDF goes in its own table, keyed by the report GUID, so listing reports never pulls
        # the base64. Add-CIPPAzDataTableEntity auto-splits the oversized property across part rows, so a
        # multi-MB report survives the Azure Table 64KB/property limit.
        if ($PdfBase64) {
            $PdfTable = Get-CippTable -tablename 'ReportBuilderPdfs'
            Add-CIPPAzDataTableEntity @PdfTable -Force -Entity @{
                PartitionKey = $TenantFilter
                RowKey       = [string]$ReportGUID
                FileName     = $PdfFileName
                Pdf          = $PdfBase64
            }
        }
        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Generated report builder report '$TemplateName' with GUID $ReportGUID" -Sev 'Info'

        # Build result message with direct link
        $CippConfigTable = Get-CippTable -tablename Config
        $CippConfig = Get-CIPPAzDataTableEntity @CippConfigTable -Filter "PartitionKey eq 'InstanceProperties' and RowKey eq 'CIPPURL'"
        $ReportLink = if ($CippConfig.Value) {
            "https://$($CippConfig.Value)/tools/report-builder/view?id=$ReportGUID"
        } else { $null }
        $ResultMessage = "Successfully generated report '$TemplateName' for $TenantFilter (GUID: $ReportGUID)"
        if ($ReportLink) {
            $ResultMessage += ". View report: $ReportLink"
        }

        # Attachments for the scheduled-email path (Send-CIPPScheduledTaskAlert forwards TaskAttachments).
        # The rendered PDF always attaches - that is the whole point of rendering server-side; the raw
        # CSV/JSON data files stay behind the IncludeRawAttachments toggle.
        $TaskAttachments = [System.Collections.Generic.List[object]]::new()

        if ($PdfBase64) {
            $TaskAttachments.Add(@{
                    Name         = $PdfFileName
                    ContentType  = 'application/pdf'
                    ContentBytes = $PdfBase64
                })
        }

        if ($IncludeRawAttachments -eq 'true') {
            foreach ($Block in $EnrichedBlocks) {
                if ($Block.type -ne 'database' -or -not $Block.dbType) { continue }
                $Format = if ($Block.format) { $Block.format } else { 'csv' }
                $FileName = "$($Block.title ?? $Block.dbType)_$TenantFilter"
                $FileName = $FileName -replace '[^a-zA-Z0-9_\-]', '_'
                switch ($Format) {
                    'json' {
                        $FileContent = $Block.content
                        $FileName += '.json'
                        $ContentType = 'application/json'
                    }
                    'csv' {
                        $FileContent = $Block.content
                        $FileName += '.csv'
                        $ContentType = 'text/csv'
                    }
                    default {
                        # For text/markdown, export as CSV for attachment
                        try {
                            $DbData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Block.dbType
                            $SelectedHeaders = @($Block.selectedHeaders)
                            $Rows = @(@($DbData) | ForEach-Object {
                                    $Row = $_
                                    $Obj = [ordered]@{}
                                    foreach ($Header in $SelectedHeaders) {
                                        $Val = $Row.$Header
                                        $Obj[$Header] = if ($null -ne $Val) { & $ResolveCellValue $Val $Header $Row } else { '' }
                                    }
                                    [PSCustomObject]$Obj
                                })
                            $FileContent = ($Rows | ConvertTo-Csv -NoTypeInformation) -join "`n"
                        } catch {
                            $FileContent = $Block.content
                        }
                        $FileName += '.csv'
                        $ContentType = 'text/csv'
                    }
                }
                $Bytes = [System.Text.Encoding]::UTF8.GetBytes($FileContent)
                $TaskAttachments.Add(@{
                        Name         = $FileName
                        ContentType  = $ContentType
                        ContentBytes = [Convert]::ToBase64String($Bytes)
                    })
            }
        }

        if ($TaskAttachments.Count -gt 0) {
            return @{
                TaskAttachments = @($TaskAttachments)
                Results         = $ResultMessage
            }
        }

        return $ResultMessage
    } catch {
        $ErrorMessage = Get-CippException -Exception $_
        Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Report generation error: $($ErrorMessage.NormalizedError)" -Sev 'Error' -LogData $ErrorMessage
        return "Error generating report: $($ErrorMessage.NormalizedError)"
    }
}
