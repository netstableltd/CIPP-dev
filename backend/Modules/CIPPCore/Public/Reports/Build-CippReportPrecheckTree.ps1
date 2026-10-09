function Build-CippReportPrecheckTree {
    <#
    .SYNOPSIS
        Composes the internal pre-check report (one or many companies) as a component tree.

    .PARAMETER Companies
        Array of @{ TenantName; TenantFilter; Findings } (Findings from Get-CIPPReportFindings).

    .PARAMETER Period
        Output of Get-CIPPReportPeriod - the customer report period being checked.

    .OUTPUTS
        @{ Blocks; Variables }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object[]]$Companies,
        [Parameter(Mandatory)]$Period
    )

    $warnC = '#744210'; $dangerC = '#742A2A'
    $tone = @{ Block = 'fail'; Fix = 'warn'; Info = '' }

    $Rows = foreach ($C in $Companies) {
        $F = @($C.Findings)
        $Block = @($F | Where-Object Severity -EQ 'Block').Count
        $Fix = @($F | Where-Object Severity -EQ 'Fix').Count
        $Info = @($F | Where-Object Severity -EQ 'Info').Count
        [PSCustomObject]@{
            company = $C.TenantName
            block   = $Block
            fix     = $Fix
            info    = $Info
            status  = $(if ($Block -gt 0) { 'Held - must fix' } elseif ($Fix -gt 0) { 'Fix before sending' } else { 'Ready' })
            tone    = $(if ($Block -gt 0) { 'fail' } elseif ($Fix -gt 0) { 'warn' } else { 'pass' })
            sort    = ($Block * 1000) + ($Fix * 10) + $Info
            source  = $C
        }
    }
    $Rows = @($Rows | Sort-Object -Property @{ Expression = 'sort'; Descending = $true }, company)
    $TotalBlock = ($Rows | Measure-Object block -Sum).Sum
    $TotalFix = ($Rows | Measure-Object fix -Sum).Sum
    $Held = @($Rows | Where-Object block -GT 0).Count
    $Ready = @($Rows | Where-Object { $_.block -eq 0 -and $_.fix -eq 0 }).Count

    $blocks = [System.Collections.Generic.List[object]]::new()
    $blocks.Add((New-CippReportPage -Title 'Pre-check Summary' -Subtitle "Customer reports for $($Period.Label)"))
    $blocks.Add((New-CippReportParagraph -Text 'Everything below is checked against the same data the customer reports will use. Block items stop a report going out until they are fixed or overridden; Fix items will appear in the customer''s recommendations if they are still open when the report is sent; Info items are for us only.'))
    $blocks.Add((New-CippReportStatRow -Stats @(
                @{ value = "$($Rows.Count)"; label = 'Companies checked' }
                @{ value = "$Held"; label = 'Held (Block)'; colour = $(if ($Held -gt 0) { $dangerC }) }
                @{ value = "$TotalFix"; label = 'Fix items'; colour = $(if ($TotalFix -gt 0) { $warnC }) }
                @{ value = "$Ready"; label = 'Ready to send' }
            )))
    $blocks.Add((New-CippReportTable -Title 'Companies' -Limit 200 -Columns @(
                @{ header = 'Company'; key = 'company'; width = 3; bold = $true }
                @{ header = 'Block'; key = 'block'; width = 0.7; align = 'right' }
                @{ header = 'Fix'; key = 'fix'; width = 0.7; align = 'right' }
                @{ header = 'Info'; key = 'info'; width = 0.7; align = 'right' }
                @{ header = 'Status'; key = 'status'; width = 1.6; toneField = 'tone' }
            ) -Rows @($Rows)))

    foreach ($Row in $Rows) {
        $F = @($Row.source.Findings)
        $blocks.Add((New-CippReportPage -Title $Row.company -Subtitle $Row.status))
        if ($F.Count -eq 0) {
            $blocks.Add((New-CippReportClearBox -Title 'No findings' -Content 'Nothing to fix before this report goes out.'))
            continue
        }
        $FindingRows = foreach ($Item in $F) {
            $Affected = if ($Item.Items.Count -gt 6) { "$(@($Item.Items | Select-Object -First 6) -join ', ') +$($Item.Items.Count - 6) more" } else { @($Item.Items) -join ', ' }
            @{
                severity = $Item.Severity
                area     = $Item.Area
                check    = $Item.Title
                detail   = $Item.Detail
                affected = $Affected
                tone     = $tone[$Item.Severity]
                customer = $(if ($Item.Customer -and $Item.Severity -ne 'Info') { 'Yes' } else { '' })
            }
        }
        $blocks.Add((New-CippReportTable -Limit 50 -Columns @(
                    @{ header = 'Severity'; key = 'severity'; width = 0.8; toneField = 'tone' }
                    @{ header = 'Check'; key = 'check'; width = 1.8; bold = $true }
                    @{ header = 'Detail'; key = 'detail'; width = 3 }
                    @{ header = 'Affected'; key = 'affected'; width = 2.2 }
                    @{ header = 'In report'; key = 'customer'; width = 0.7 }
                ) -Rows @($FindingRows)))
    }

    @{
        Blocks    = @($blocks)
        Variables = @{
            coverlabel         = 'Report Pre-check'
            covertenant        = $(if ($Rows.Count -eq 1) { $Rows[0].company } else { "$($Rows.Count) companies" })
            coversubtitle      = "Checks run before the $($Period.Label) customer reports are sent."
            covermeta          = "$Held held $([char]0x00B7) $TotalFix to fix $([char]0x00B7) $Ready ready"
            covermetanote      = 'Internal'
            coverfooternote    = "Internal $([char]0x2014) not for customers"
            coverfallbackimage = '/reportImages/city.jpg'
            footerlabel        = "Pre-check $([char]0x2014) $($Period.Label)"
        }
    }
}
