function Resolve-CippReportBuilderBlocks {
    <#
    .SYNOPSIS
        Fills Report Builder blocks with a tenant's data, ready for ConvertTo-CippReportPdf.

    .DESCRIPTION
        Extracted from Push-ExecGenerateReportBuilderReport so other report generators (for
        example the Reports area's monthly customer report, which can include Report Builder
        templates as sections) resolve template blocks exactly the way the Report Builder does:

          - live 'test' blocks get the tenant's latest test result content
          - 'database' blocks get the tenant's Reporting DB rows (licence SKUs shown by name,
            Cloud PC encryption shown as platform-managed) as text, csv or json
          - data tokens (&Users&, chart/table data sources) are resolved by
            Resolve-CippReportDataToken

    .PARAMETER Blocks
        Parsed template blocks (objects, not JSON).

    .PARAMETER TenantFilter
        Tenant default domain.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Blocks,
        [Parameter(Mandatory = $true)][string]$TenantFilter
    )

    $ParsedBlocks = @($Blocks)

    # Licence assignments come out of the users cache as objects carrying skuId GUIDs; a
    # report reader wants product names. The tenant's LicenseOverview cache already carries
    # the display name per SKU with the ExcludedLicenses table applied, so cells shaped like
    # licence assignments render through it: known SKUs become their product name and
    # excluded SKUs drop out, matching every other licence view in CIPP. Without overview
    # data the cell is left untouched rather than guessed at.
    $LicenseNamesBySkuId = @{}
    if ($ParsedBlocks | Where-Object { $_.type -eq 'database' -and $_.dbType }) {
        try {
            foreach ($License in @(New-CIPPDbRequest -TenantFilter $TenantFilter -Type 'LicenseOverview' -Fields 'License', 'skuId')) {
                if ($License.skuId) { $LicenseNamesBySkuId[([string]$License.skuId).ToLowerInvariant()] = [string]$License.License }
            }
        } catch {
            Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Could not load the licence overview cache; licence columns will show raw SKU ids: $($_.Exception.Message)" -Sev 'Warning'
        }
    }
    $ResolveCellValue = {
        param($Value, $Header, $Row)
        # Windows 365 Cloud PCs never report BitLocker (isEncrypted stays false) although
        # their disks are platform-encrypted by Azure - rendered as a distinct state so the
        # device is not flagged as an encryption risk. Mirrored by the report builder's
        # client-side preview (formatDatabaseContent).
        if ($Header -eq 'isEncrypted' -and $Value -ne $true -and $Row -and (Test-CIPPCloudPCDevice -Device $Row)) {
            return 'Encrypted (platform-managed)'
        }
        $Items = @($Value)
        if ($LicenseNamesBySkuId.Count -eq 0 -or $Items.Count -eq 0 -or $null -eq $Items[0] -or -not $Items[0].PSObject.Properties['skuId']) {
            return $Value
        }
        $Names = foreach ($Assignment in $Items) {
            $Name = $LicenseNamesBySkuId[([string]$Assignment.skuId).ToLowerInvariant()]
            if ($Name) { $Name }
        }
        return (@($Names) -join ', ')
    }

    # For test blocks that are NOT static, fetch fresh test results
    $TestResults = $null
    $HasLiveTests = $ParsedBlocks | Where-Object { $_.type -eq 'test' -and $_.static -ne $true }
    if ($HasLiveTests) {
        $TestTable = Get-CippTable -tablename 'CippTestResults'
        $TestFilter = "PartitionKey eq '$TenantFilter'"
        $TestResults = @(Get-CIPPAzDataTableEntity @TestTable -Filter $TestFilter)
    }

    # Build enriched blocks with fresh content
    $EnrichedBlocks = @($ParsedBlocks | ForEach-Object {
            $Block = $_

            # Enrich live test blocks
            if ($Block.type -eq 'test' -and $Block.static -ne $true -and $TestResults) {
                $TestResult = $TestResults | Where-Object { $_.TestId -eq $Block.testId -or $_.RowKey -eq $Block.testId } | Select-Object -First 1
                if ($TestResult) {
                    if ($TestResult.TestType -eq 'Custom' -and $TestResult.ResultDataJson -and $TestResult.MarkdownTemplate) {
                        $Block.content = $TestResult.MarkdownTemplate
                    } elseif ($TestResult.ResultMarkdown) {
                        $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue $TestResult.ResultMarkdown -Force
                    }
                }
            }

            # Enrich database blocks
            if ($Block.type -eq 'database' -and $Block.dbType) {
                try {
                    $DbData = New-CIPPDbRequest -TenantFilter $TenantFilter -Type $Block.dbType
                    if ($null -ne $DbData) {
                        $FirstItem = if ($DbData -is [array]) { $DbData[0] } else { $DbData }
                        $SelectedHeaders = @($Block.selectedHeaders)
                        if ($SelectedHeaders.Count -eq 0) {
                            $ExcludedHeaders = @('id', 'rowkey', 'partitionkey', 'etag', 'timestamp')
                            $AllHeaders = @($FirstItem.PSObject.Properties.Name | Where-Object { $_.ToLower() -notin $ExcludedHeaders }) | Sort-Object
                            $SelectedHeaders = $AllHeaders
                        }
                        $Format = if ($Block.format) { $Block.format } else { 'text' }
                        $FilteredData = @(@($DbData) | ForEach-Object {
                                $Row = $_
                                $Obj = [ordered]@{}
                                foreach ($Header in $SelectedHeaders) {
                                    $Val = $Row.$Header
                                    $Obj[$Header] = if ($null -ne $Val) { & $ResolveCellValue $Val $Header $Row } else { '' }
                                }
                                [PSCustomObject]$Obj
                            })

                        $BlockContent = switch ($Format) {
                            'json' {
                                ConvertTo-Json -InputObject @($FilteredData) -Depth 10 -Compress
                            }
                            'csv' {
                                ($FilteredData | ConvertTo-Csv -NoTypeInformation) -join "`n"
                            }
                            default {
                                $HeaderLine = '| ' + ($SelectedHeaders -join ' | ') + ' |'
                                $SeparatorLine = '| ' + (($SelectedHeaders | ForEach-Object { '---' }) -join ' | ') + ' |'
                                $DataLines = @($FilteredData | ForEach-Object {
                                        $DataRow = $_
                                        $Cells = $SelectedHeaders | ForEach-Object {
                                            $Val = $DataRow.$_
                                            if ($null -eq $Val) { '' }
                                            elseif ($Val -is [PSCustomObject] -or $Val -is [hashtable]) { ConvertTo-Json -InputObject $Val -Depth 5 -Compress }
                                            else { "$Val" -replace '\|', '\|' -replace "`n", ' ' }
                                        }
                                        '| ' + ($Cells -join ' | ') + ' |'
                                    })
                                (@($HeaderLine, $SeparatorLine) + $DataLines) -join "`n"
                            }
                        }
                        $Block | Add-Member -NotePropertyMembers ([ordered]@{
                                content = $BlockContent
                                static  = $true
                            }) -Force
                    } else {
                        $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue 'No data available for this data source.' -Force
                    }
                } catch {
                    $DbError = Get-CippException -Exception $_
                    Write-LogMessage -API 'ReportBuilder' -tenant $TenantFilter -message "Failed to fetch database data for type $($Block.dbType): $($DbError.NormalizedError)" -Sev 'Warning' -LogData $DbError
                    $Block | Add-Member -NotePropertyName 'content' -NotePropertyValue "Error fetching data: $($DbError.NormalizedError)" -Force
                }
            }

            $Block
        })

    # Data tokens (&Users&, &Devices.complianceState=compliant&, a chart or table's data source)
    # resolve against the reporting database here, on the server, so a scheduled run and a
    # preview read the same data.
    $EnrichedBlocks = @(Resolve-CippReportDataToken -Blocks $EnrichedBlocks -TenantFilter $TenantFilter)

    return @($EnrichedBlocks)
}
