function Get-CIPPClaudeConnectorScopeSummary {
    <#
    .SYNOPSIS
        Describes a set of Graph scopes in Claude for Microsoft 365 terms: which read areas are on, which
        write scopes are present, and which access level that matches.

    .OUTPUTS
        @{ ReadAreas = @(area ids that are on); WriteScopes = @(...); Level = level id, or 'custom' when the
           write scopes match no level }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string[]]$Scopes = @())

    $Config = Get-CIPPClaudeConnectorAccessConfig
    $Set = @($Scopes | Where-Object { $_ })
    $Areas = @($Config.readAreas | Where-Object { $Area = $_; @($Area.scopes | Where-Object { $Set -contains $_ }).Count -gt 0 } | ForEach-Object { $_.id })
    $Write = @($Config.writeScopes | Where-Object { $Set -contains $_ })
    $Level = 'custom'
    foreach ($L in $Config.levels) {
        $Want = @($L.scopes)
        if ($Want.Count -eq $Write.Count -and -not ($Want | Where-Object { $Write -notcontains $_ })) { $Level = $L.id; break }
    }
    [pscustomobject]@{ ReadAreas = $Areas; WriteScopes = $Write; Level = $Level }
}
