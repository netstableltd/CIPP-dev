function Get-CIPPChatGPTConnectorScopeSummary {
    <#
    .SYNOPSIS
        Describes a set of Graph scopes in ChatGPT for Microsoft 365 terms: which read areas are on, which
        write scopes are present, and which access level that matches.

    .OUTPUTS
        @{ ReadAreas = @(area ids that are on); WriteScopes = @(...); Level = level id, or 'custom' when the
           write scopes match no level; Extras = @(extra ids on top of that level) }

        The write scopes match a level exactly, or the highest level they include plus whole extras
        (for example Level 3 and Post in Teams). Anything else is 'custom'.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string[]]$Scopes = @())

    $Config = Get-CIPPChatGPTConnectorAccessConfig
    $Set = @($Scopes | Where-Object { $_ })
    $Areas = @($Config.readAreas | Where-Object { $Area = $_; @($Area.scopes | Where-Object { $Set -contains $_ }).Count -gt 0 } | ForEach-Object { $_.id })
    $Write = @($Config.writeScopes | Where-Object { $Set -contains $_ })
    $Level = 'custom'
    $Extras = @()
    foreach ($L in $Config.levels) {
        $Want = @($L.scopes)
        if ($Want.Count -eq $Write.Count -and -not ($Want | Where-Object { $Write -notcontains $_ })) { $Level = $L.id; break }
    }
    if ($Level -eq 'custom') {
        # The highest level whose scopes are all there; the rest must be made up of whole extras.
        $Base = @($Config.levels | Sort-Object { [int]$_.number } -Descending | Where-Object { $L = $_; -not (@($L.scopes) | Where-Object { $Write -notcontains $_ }) }) | Select-Object -First 1
        if ($Base) {
            $Rest = @($Write | Where-Object { @($Base.scopes) -notcontains $_ })
            $Found = @($Config.extras | Where-Object { $E = $_; @($E.scopes | Where-Object { $Rest -contains $_ }).Count -gt 0 })
            $Whole = -not ($Found | Where-Object { $E = $_; @($E.scopes | Where-Object { $Write -notcontains $_ }).Count -gt 0 })
            $Covered = -not ($Rest | Where-Object { $S = $_; -not ($Found | Where-Object { @($_.scopes) -contains $S }) })
            if ($Found.Count -gt 0 -and $Whole -and $Covered) { $Level = $Base.id; $Extras = @($Found | ForEach-Object { $_.id }) }
        }
    }
    [pscustomobject]@{ ReadAreas = $Areas; WriteScopes = $Write; Level = $Level; Extras = $Extras }
}
