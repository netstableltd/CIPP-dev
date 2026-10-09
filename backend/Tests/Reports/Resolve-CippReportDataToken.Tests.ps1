# Pester tests for the report builder's data tokens: what &Users&, &Users.displayName&,
# &Devices.complianceState=compliant& and the chart/table sources resolve to, from a stubbed
# reporting database.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))
    . (Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter 'Resolve-CippReportDataToken.ps1' | Select-Object -First 1 -ExpandProperty FullName)

    $script:Db = @{
        Users   = @(
            [PSCustomObject]@{ displayName = 'Adele Vance'; accountEnabled = $true; assignedLicenses = @(@{ skuId = 'e3' }, @{ skuId = 'p1' }) }
            [PSCustomObject]@{ displayName = 'Alex Wilber'; accountEnabled = $true; assignedLicenses = @(@{ skuId = 'e3' }) }
            [PSCustomObject]@{ displayName = 'Guest User'; accountEnabled = $false; assignedLicenses = @() }
        )
        SecureScore = @(
            [PSCustomObject]@{ createdDateTime = '2026-08-24T00:00:00Z'; currentScore = 213.71; maxScore = 273 }
            [PSCustomObject]@{ createdDateTime = '2026-08-22T00:00:00Z'; currentScore = 210.5; maxScore = 273 }
            [PSCustomObject]@{ createdDateTime = '2026-08-23T00:00:00Z'; currentScore = 213.69; maxScore = 273 }
        )
        Mailboxes = @(
            [PSCustomObject]@{ UPN = 'a@x'; department = 'Sales'; TotalItemSize = 10 }
            [PSCustomObject]@{ UPN = 'b@x'; department = 'sales'; TotalItemSize = 5 }
            [PSCustomObject]@{ UPN = 'c@x'; department = 'IT'; TotalItemSize = 40 }
        )
        Tickets = @(
            [PSCustomObject]@{ TicketID = 1; TicketCreatedDate = '2026-09-02T09:00:00Z'; Priority = 'High' }
            [PSCustomObject]@{ TicketID = 2; TicketCreatedDate = '2026-09-30T23:59:00Z'; Priority = 'Low' }
            [PSCustomObject]@{ TicketID = 3; TicketCreatedDate = '2026-10-03T09:00:00Z'; Priority = 'Low' }
            [PSCustomObject]@{ TicketID = 4; TicketCreatedDate = '2026-08-31T23:00:00Z'; Priority = 'Low' }
            [PSCustomObject]@{ TicketID = 5; TicketCreatedDate = 'not a date'; Priority = 'Low' }
        )
        Devices = @(
            [PSCustomObject]@{ deviceName = 'PC1'; operatingSystem = 'Windows'; complianceState = 'compliant'; storageTotal = 512 }
            [PSCustomObject]@{ deviceName = 'PC2'; operatingSystem = 'Windows'; complianceState = 'noncompliant'; storageTotal = 256 }
            [PSCustomObject]@{ deviceName = 'MAC1'; operatingSystem = 'macOS'; complianceState = 'compliant'; storageTotal = 1024 }
            [PSCustomObject]@{ deviceName = 'PHONE'; operatingSystem = $null; complianceState = 'Compliant'; storageTotal = 64 }
        )
    }
    $script:Reads = 0
    function New-CIPPDbRequest {
        param($TenantFilter, $Type, $Fields)
        $script:Reads++
        if ($script:Db.ContainsKey($Type)) { $script:Db[$Type] } else { throw "No cache for $Type" }
    }
    function Resolve-Blocks($Blocks) {
        $Out = @(Resolve-CippReportDataToken -Blocks $Blocks -TenantFilter 'contoso.onmicrosoft.com')
        # one element per block, never a wrapped array: that is what blanked every preview once
        $Out.Count | Should -Be @($Blocks).Count
        foreach ($b in $Out) { $b -is [array] | Should -BeFalse }
        # kept an array for the tests' indexing; a lone block would otherwise unroll to itself
        , $Out
    }
}

Describe 'Resolve-CippReportDataToken' {
    BeforeEach { $script:Reads = 0 }

    It 'counts a collection, lists a field and counts the rows that match' {
        $Blocks = Resolve-Blocks @(@{ type = 'blank'; content = '<p>&amp;Users&amp; users: &amp;Users.displayName&amp;. Enabled: &Users.accountEnabled=true&, disabled: &Users.accountEnabled!=true&.</p>' })
        $Blocks[0].content | Should -Be '<p>3 users: Adele Vance, Alex Wilber, Guest User. Enabled: 2, disabled: 1.</p>'
    }

    It 'reaches into nested objects and arrays, and wildcards a filter' {
        $Blocks = Resolve-Blocks @(@{ type = 'note'; content = 'Licences: &Users.assignedLicenses.skuId&; E3 holders: &Users.assignedLicenses.skuId=e3&; Windows-ish: &Devices.operatingSystem=Win*&' })
        $Blocks[0].content | Should -Be 'Licences: e3, p1; E3 holders: 2; Windows-ish: 2'
    }

    It 'aggregates a numeric field' {
        $Blocks = Resolve-Blocks @(@{ type = 'scorecard'; stats = @(@{ label = 'Storage'; value = '&Devices.storageTotal:sum& GB' }, @{ label = 'Average'; value = '&Devices.storageTotal:avg&' }, @{ label = 'Largest'; value = '&Devices.storageTotal:max&' }) })
        $Blocks[0].stats[0].value | Should -Be '1856 GB'
        $Blocks[0].stats[1].value | Should -Be 464
        $Blocks[0].stats[2].value | Should -Be 1024
    }

    It 'turns a lone numeric token into a number, so bars and points can use one' {
        $Blocks = Resolve-Blocks @(@{ type = 'progress'; items = @(@{ label = 'Compliant'; value = '&Devices.complianceState=compliant&'; max = '&Devices&' }) })
        $Blocks[0].items[0].value | Should -Be 3
        $Blocks[0].items[0].value | Should -BeOfType [double]
        $Blocks[0].items[0].max | Should -Be 4
    }

    It 'leaves a token that names nothing as written, and reads each collection once' {
        $Blocks = Resolve-Blocks @(@{ type = 'blank'; content = '&Nope& and &Nope.x& stay; &Users& and &Users& resolve' }, @{ type = 'note'; content = '&Users.displayName=Adele Vance&' })
        $Blocks[0].content | Should -Be '&Nope& and &Nope.x& stay; 3 and 3 resolve'
        $Blocks[1].content | Should -Be '1'
        $script:Reads | Should -Be 2
    }

    It 'fills a chart with one slice per value of the field, blanks counted apart' {
        $Blocks = Resolve-Blocks @(@{ type = 'chart'; title = 'OS'; chartKind = 'donut'; chartSource = '&Devices.operatingSystem&'; chartData = @(@{ label = 'placeholder'; value = 0 }) })
        $Points = @($Blocks[0].chartData)
        $Points.Count | Should -Be 3
        $Points[0].label | Should -Be 'Windows'
        $Points[0].value | Should -Be 2
        $Points[1].label | Should -Be 'macOS'
        $Points[2].label | Should -Be '(blank)'
        $Blocks[0].chartSource | Should -Be '&Devices.operatingSystem&'
    }

    It 'fills a chart with a single counted slice when the source has no field to group by' {
        $Blocks = Resolve-Blocks @(@{ type = 'chart'; title = 'Compliant devices'; chartSource = '&Devices.complianceState=compliant&'; chartData = @() })
        @($Blocks[0].chartData).Count | Should -Be 1
        $Blocks[0].chartData[0].label | Should -Be 'Compliant devices'
        $Blocks[0].chartData[0].value | Should -Be 3
    }

    It 'fills a table from the rows a filter keeps, each column reading its field or header' {
        $Blocks = Resolve-Blocks @(@{
                type = 'richtable'; dataSource = '&Devices.complianceState=compliant&'
                columns = @(@{ header = 'Device'; key = 'c1'; field = 'deviceName' }, @{ header = 'operatingSystem'; key = 'c2' })
                rows = @(@{ c1 = 'typed'; c2 = 'rows' })
            })
        $Rows = @($Blocks[0].rows)
        $Rows.Count | Should -Be 3
        $Rows[0].c1 | Should -Be 'PC1'
        $Rows[0].c2 | Should -Be 'Windows'
        $Rows[2].c2 | Should -Be ''
        $Blocks[0].limit | Should -Be 200
    }

    It 'fills a chart from a picked source, grouping the rows the condition keeps' {
        $Blocks = Resolve-Blocks @(@{ type = 'chart'; title = 'Compliant by OS'; chartSource = @{ type = 'Devices'; field = 'operatingSystem'; filter = @{ field = 'complianceState'; op = '='; value = 'compliant' } }; chartData = @() })
        $Points = @($Blocks[0].chartData)
        ($Points | ForEach-Object { "$($_.label)=$($_.value)" }) -join ';' | Should -Be 'macOS=1;Windows=1;(blank)=1'
    }

    It 'plots a value per row in date order, as a Secure Score trend needs' {
        $Blocks = Resolve-Blocks @(@{ type = 'chart'; chartKind = 'trend'; chartSource = @{ type = 'SecureScore'; field = 'createdDateTime'; valueField = 'currentScore'; filter = $null }; chartData = @() })
        ($Blocks[0].chartData | ForEach-Object { "$($_.label)=$($_.value)" }) -join ';' | Should -Be 'Aug 22=210.5;Aug 23=213.69;Aug 24=213.71'
    }

    It 'plots a value per row in row order when the labels are not dates, and treats Count of rows as counting' {
        $Blocks = Resolve-Blocks @(
            @{ type = 'chart'; chartKind = 'bar'; chartSource = @{ type = 'Mailboxes'; field = 'UPN'; valueField = 'TotalItemSize'; filter = $null }; chartData = @() }
            @{ type = 'chart'; chartKind = 'bar'; chartSource = @{ type = 'Mailboxes'; field = 'department'; valueField = '__count'; filter = $null }; chartData = @() }
        )
        ($Blocks[0].chartData | ForEach-Object { "$($_.label)=$($_.value)" }) -join ';' | Should -Be 'a@x=10;b@x=5;c@x=40'
        ($Blocks[1].chartData | ForEach-Object { "$($_.label)=$($_.value)" }) -join ';' | Should -Be 'Sales=2;IT=1'
    }

    It 'combines the rows sharing a label with the chosen aggregate' {
        $Blocks = Resolve-Blocks @(@{ type = 'chart'; chartKind = 'bar'; chartSource = @{ type = 'Mailboxes'; field = 'department'; valueField = 'TotalItemSize'; aggregate = 'sum'; filter = $null }; chartData = @() })
        ($Blocks[0].chartData | ForEach-Object { "$($_.label)=$($_.value)" }) -join ';' | Should -Be 'IT=40;Sales=15'
    }

    It 'counts a picked source with no field as one slice' {
        $Blocks = Resolve-Blocks @(@{ type = 'chart'; title = 'Devices'; chartSource = @{ type = 'Devices'; field = $null; filter = $null }; chartData = @() })
        $Blocks[0].chartData[0].value | Should -Be 4
    }

    It 'fills a table from a picked source' {
        $Blocks = Resolve-Blocks @(@{ type = 'richtable'; dataSource = @{ type = 'Users'; filter = @{ field = 'accountEnabled'; op = '!='; value = 'true' } }; columns = @(@{ header = 'Name'; key = 'c1'; field = 'displayName' }); rows = @() })
        @($Blocks[0].rows).Count | Should -Be 1
        $Blocks[0].rows[0].c1 | Should -Be 'Guest User'
    }

    It 'keeps typed rows when the table source names nothing' {
        $Blocks = Resolve-Blocks @(@{ type = 'richtable'; dataSource = '&Nothing&'; columns = @(@{ header = 'A'; key = 'c1' }); rows = @(@{ c1 = 'typed' }) })
        $Blocks[0].rows[0].c1 | Should -Be 'typed'
    }

    It 'walks objects parsed from JSON the way the generator hands them over' {
        $Json = '[{"type":"scorecard","stats":[{"label":"Users","value":"&Users&"}]},{"type":"page","title":"&Devices& devices","subtitle":"x"}]'
        $Blocks = Resolve-Blocks @(ConvertFrom-Json -InputObject $Json)
        $Blocks[0].stats[0].value | Should -Be 3
        $Blocks[1].title | Should -Be '4 devices'
    }

    Context 'date ranges' {
        BeforeAll {
            $script:Now = [datetime]::new(2026, 10, 9, 12, 0, 0, [DateTimeKind]::Utc)
            function Resolve-At($Blocks, $Period) {
                , @(Resolve-CippReportDataToken -Blocks $Blocks -TenantFilter 'contoso.onmicrosoft.com' -Now $script:Now -Period $Period)
            }
        }

        It 'counts rows whose date falls in <Window>' -ForEach @(
            @{ Window = 'last-month'; Expected = 2 }
            @{ Window = 'period'; Expected = 2 }
            @{ Window = 'this-month'; Expected = 1 }
            @{ Window = 'last-7-days'; Expected = 1 }
            @{ Window = 'last-40-days'; Expected = 4 }
            @{ Window = 'older-than-30-days'; Expected = 2 }
            @{ Window = 'nonsense'; Expected = 0 }
        ) {
            $Blocks = Resolve-At @(@{ type = 'blank'; content = "&Tickets.TicketCreatedDate@$Window&" })
            $Blocks[0].content | Should -Be "$Expected"
        }

        It 'shows dates in tables as d MMM yyyy, whether parsed as dates or left as ISO text' {
            $Blocks = Resolve-At @(@{ type = 'richtable'; dataSource = @{ type = 'Tickets'; filter = @{ field = 'TicketID'; op = '='; value = '1' } }; columns = @(@{ key = 'd'; field = 'TicketCreatedDate' }) })
            $Blocks[0].rows[0].d | Should -Be '2 Sep 2026 09:00'
            $script:Db.Parsed = @([PSCustomObject]@{ When = [datetime]::new(2026, 9, 25, 0, 0, 0, [DateTimeKind]::Utc) })
            $Blocks = Resolve-At @(@{ type = 'richtable'; dataSource = @{ type = 'Parsed' }; columns = @(@{ key = 'd'; field = 'When' }) })
            $Blocks[0].rows[0].d | Should -Be '25 Sep 2026'
        }

        It 'reads "period" as the report period when one is given' {
            $Period = @{ Start = [datetime]::new(2026, 8, 1, 0, 0, 0, [DateTimeKind]::Utc); End = [datetime]::new(2026, 9, 1, 0, 0, 0, [DateTimeKind]::Utc) }
            $Blocks = Resolve-At @(@{ type = 'blank'; content = '&Tickets.TicketCreatedDate@period&' }) $Period
            $Blocks[0].content | Should -Be '1'
        }

        It 'filters a picked source with the "in" condition' {
            $Blocks = Resolve-At @(
                @{ type = 'chart'; chartSource = @{ type = 'Tickets'; field = 'Priority'; filter = @{ field = 'TicketCreatedDate'; op = 'in'; value = 'last-month' } } }
                @{ type = 'richtable'; dataSource = @{ type = 'Tickets'; filter = @{ field = 'TicketCreatedDate'; op = 'in'; value = 'this-month' } }; columns = @(@{ key = 'id'; field = 'TicketID' }) }
            )
            @($Blocks[0].chartData | ForEach-Object { "$($_.label)=$($_.value)" }) | Should -Be @('High=1', 'Low=1')
            @($Blocks[1].rows).Count | Should -Be 1
            $Blocks[1].rows[0].id | Should -Be '3'
        }
    }
}
