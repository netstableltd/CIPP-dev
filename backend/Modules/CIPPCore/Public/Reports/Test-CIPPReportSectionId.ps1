function Test-CIPPReportSectionId {
    <#
    .SYNOPSIS
        Returns $true when a section id is a built-in customer report section or a Report Builder template reference.

    .DESCRIPTION
        Valid ids are the values from Get-CIPPReportSectionCatalog -BuiltInOnly, or 'template:<RowKey>'
        where the RowKey is a GUID-like id (letters, digits and dashes). Whether the template still
        exists is checked at generation time, not here, so deleting a template never blocks saving.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([string]$Id)

    if ([string]::IsNullOrWhiteSpace($Id)) { return $false }
    if ($Id -match '^template:[A-Za-z0-9-]{1,64}$') { return $true }
    return $Id -in @((Get-CIPPReportSectionCatalog -BuiltInOnly).value)
}
