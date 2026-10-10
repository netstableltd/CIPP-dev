function ConvertTo-AteraCpuInfo {
    <#
    .SYNOPSIS
        Reads an Atera processor string ('Intel(R) Core(TM) i5-8500T CPU @ 2.10GHz') into a short summary,
        vendor, generation, approximate launch year and whether it can run Windows 11.

    .OUTPUTS
        @{ Summary; Vendor = 'Intel'|'AMD'|''; Family = 'Core'|'Ryzen'|'Xeon'|...; Generation (Intel Core generation, or
           Ryzen series as 1-9 for 1000-9000; Intel Core Ultra and Core 3/5/7 = 14); Year; Win11 = 'Yes'|'No'|'Unknown';
           EntryLevel (Celeron, Pentium, Atom, Athlon, AMD A-series, Core 2) }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Processor)

    $IntelYear = @{ 1 = 2010; 2 = 2011; 3 = 2012; 4 = 2013; 5 = 2015; 6 = 2015; 7 = 2017; 8 = 2018; 9 = 2019; 10 = 2020; 11 = 2021; 12 = 2022; 13 = 2023; 14 = 2024 }
    $AmdYear = @{ 1 = 2017; 2 = 2018; 3 = 2019; 4 = 2020; 5 = 2021; 6 = 2022; 7 = 2023; 8 = 2024; 9 = 2024 }
    $Ordinal = { param([int]$N) "$N$(if ($N % 100 -in 11..13) { 'th' } else { switch ($N % 10) { 1 { 'st' } 2 { 'nd' } 3 { 'rd' } default { 'th' } } })" }

    $Cpu = ("$Processor" -replace '\((R|TM|tm|r)\)', '' -replace '\s+', ' ').Trim()
    $Info = @{ Summary = $Cpu; Vendor = ''; Family = ''; Generation = $null; Year = $null; Win11 = 'Unknown'; EntryLevel = $false }

    if ($Cpu -match 'Core Ultra (X?\d)') {
        $Info.Summary = "Intel Core Ultra $($Matches[1])"; $Info.Vendor = 'Intel'; $Info.Family = 'Core'; $Info.Generation = 14; $Info.Year = 2024; $Info.Win11 = 'Yes'
    } elseif ($Cpu -match 'Core ([3579]) (\d)\d{2}[A-Z]') {
        # Intel Core 3/5/7 (Series 1 and later, 2023+): 'Core 7 150U'
        $Info.Summary = "Intel Core $($Matches[1])"; $Info.Vendor = 'Intel'; $Info.Family = 'Core'; $Info.Generation = 14; $Info.Year = 2023; $Info.Win11 = 'Yes'
    } elseif ($Cpu -match 'Core (i[3579]) CPU [A-Z]? ?(\d{3})\b') {
        # 1st generation (2010): 'Core i7 CPU L 640', 'Core i3 CPU M 380', 'Core i7 CPU 860'
        $Info.Summary = "Intel Core $($Matches[1]), 1st gen"; $Info.Vendor = 'Intel'; $Info.Family = 'Core'; $Info.Generation = 1; $Info.Year = 2010; $Info.Win11 = 'No'
    } elseif ($Cpu -match 'Core (i[3579])[- ](\d{3,5})([A-Z]\w*)?') {
        $Family = $Matches[1]; $Model = $Matches[2]; $Suffix = "$($Matches[3])"
        $Gen = if ($Model.Length -eq 5) { [int]$Model.Substring(0, 2) } elseif ($Model.Length -eq 4 -and $Suffix -match '^G\d' -and $Model -match '^1[01]') { [int]$Model.Substring(0, 2) } elseif ($Model.Length -eq 4) { [int]$Model.Substring(0, 1) } else { 1 }
        if ($Cpu -match '(\d{1,2})th Gen') { $Gen = [int]$Matches[1] }
        $Info.Vendor = 'Intel'; $Info.Family = 'Core'; $Info.Generation = $Gen; $Info.Year = $IntelYear[$Gen]
        $Info.Win11 = if ($Gen -ge 8) { 'Yes' } else { 'No' }
        $Info.Summary = "Intel Core $Family, $(& $Ordinal $Gen) gen"
    } elseif ($Cpu -match 'Ryzen (\d)( PRO)? (\d)(\d{3})([A-Z]*)') {
        $Tier = [int]$Matches[1]; $Series = [int]$Matches[3]; $AmdSuffix = "$($Matches[5])"
        $Info.Vendor = 'AMD'; $Info.Family = 'Ryzen'; $Info.Generation = $Series; $Info.Year = $AmdYear[$Series]
        # Ryzen 1000 and the 2000-series APUs (2200G/2400G, 2x00U/H - first-generation Zen) are not on
        # Microsoft's Windows 11 list; 2000-series desktop CPUs (Zen+) and later are.
        $Info.Win11 = if ($Series -ge 3 -or ($Series -eq 2 -and $AmdSuffix -notmatch '^(G|GE|U|H|HS)$')) { 'Yes' } else { 'No' }
        $Info.Summary = "AMD Ryzen $Tier $($Series)000 series"
    } elseif ($Cpu -match 'Ryzen (\d) Microsoft Surface') {
        # Surface Laptop 3/4 custom parts (3780U / 4980U): both on Microsoft's Windows 11 list.
        $Info.Summary = "AMD Ryzen $($Matches[1]) (Surface)"; $Info.Vendor = 'AMD'; $Info.Family = 'Ryzen'; $Info.Win11 = 'Yes'
    } elseif ($Cpu -match 'Ryzen AI') {
        $Info.Summary = 'AMD Ryzen AI'; $Info.Vendor = 'AMD'; $Info.Family = 'Ryzen'; $Info.Generation = 9; $Info.Year = 2024; $Info.Win11 = 'Yes'
    } elseif ($Cpu -match 'Xeon.*\bE[357]-\d{4}\w?\s*v(\d)') {
        $Info.Year = @{ 1 = 2011; 2 = 2012; 3 = 2013; 4 = 2015; 5 = 2015; 6 = 2017 }[[int]$Matches[1]]
        $Info.Summary = "Intel Xeon (v$($Matches[1]))"; $Info.Vendor = 'Intel'; $Info.Family = 'Xeon'; $Info.Win11 = 'No'
    } elseif ($Cpu -match 'Xeon.*\bE\d{4,5}\b') {
        $Info.Summary = 'Intel Xeon'; $Info.Vendor = 'Intel'; $Info.Family = 'Xeon'; $Info.Year = 2010; $Info.Win11 = 'No'
    } elseif ($Cpu -match 'Xeon') {
        $Info.Summary = 'Intel Xeon'; $Info.Vendor = 'Intel'; $Info.Family = 'Xeon'
    } elseif ($Cpu -match 'AMD FX') {
        $Info.Summary = 'AMD FX'; $Info.Vendor = 'AMD'; $Info.Family = 'FX'; $Info.Year = 2012; $Info.Win11 = 'No'; $Info.EntryLevel = $true
    } elseif ($Cpu -match 'Celeron|Pentium|Atom|Athlon|AMD A\d|Core2|Core 2') {
        $Info.Summary = "$(($Cpu -split ' CPU| @')[0])"; $Info.EntryLevel = $true
        $Info.Vendor = if ($Cpu -match 'AMD|Athlon') { 'AMD' } else { 'Intel' }
        if ($Cpu -match 'Core ?2|Atom') { $Info.Win11 = 'No' }
    }
    if ($Info.Year) { $Info.Summary = "$($Info.Summary) (c. $($Info.Year))" }
    $Info
}
