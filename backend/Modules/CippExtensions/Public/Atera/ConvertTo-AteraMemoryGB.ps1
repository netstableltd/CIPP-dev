function ConvertTo-AteraMemoryGB {
    <#
    .SYNOPSIS
        Turns the memory Windows reports (Atera's Memory, in MB) into the memory fitted, in GB.

    .DESCRIPTION
        Windows reports usable memory, which is less than what is fitted when the graphics share it:
        an 8 GB Surface Laptop shows 7,631 MB and a 16 GB Ryzen desktop 14,254 MB. This rounds up to the
        nearest common size when the reported figure is at least 85% of it (7,631 MB -> 8 GB), and
        otherwise rounds to the nearest GB.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($MemoryMB)

    if ($null -eq $MemoryMB -or "$MemoryMB" -eq '' -or [double]$MemoryMB -le 0) { return $null }
    $MB = [double]$MemoryMB
    foreach ($Size in @(1, 2, 3, 4, 6, 8, 12, 16, 20, 24, 32, 48, 64, 96, 128, 192, 256, 384, 512, 768, 1024)) {
        $Full = $Size * 1024
        if ($MB -le $Full) {
            if ($MB -ge 0.85 * $Full) { return $Size }
            break
        }
    }
    [int][math]::Round($MB / 1024)
}
