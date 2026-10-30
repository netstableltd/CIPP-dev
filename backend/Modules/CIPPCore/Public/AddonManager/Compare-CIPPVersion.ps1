function Compare-CIPPVersion {
    <#
    .SYNOPSIS
        Compares two versions like 11.2.1 (anything after +, - or a space is ignored). Returns -1, 0 or 1.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$A, [string]$B)

    $Parse = {
        param($V)
        $Core = ("$V".Trim() -split '[+\-\s]')[0]
        $Parts = @($Core -split '\.' | ForEach-Object { $N = 0; [void][int]::TryParse($_, [ref]$N); $N })
        while ($Parts.Count -lt 3) { $Parts += 0 }
        $Parts
    }
    $X = & $Parse $A; $Y = & $Parse $B
    for ($i = 0; $i -lt 3; $i++) {
        if ($X[$i] -lt $Y[$i]) { return -1 }
        if ($X[$i] -gt $Y[$i]) { return 1 }
    }
    0
}
