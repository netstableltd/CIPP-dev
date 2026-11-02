function Get-CIPPAddonGuide {
    <#
    .SYNOPSIS
        A how-to guide (a Word document) uploaded for an add-on, if there is one.

    .DESCRIPTION
        Add-ons can take the MSP's own guides, such as "Sending from a shared mailbox" with screenshots, to
        add to the end of a PDF for the customer. They are listed under guides in the add-on's addon.json,
        uploaded with ExecAddonGuide and kept in this CIPP instance (table AddonGuides, PartitionKey the
        add-on id, RowKey the guide key), not in the code: they are the MSP's content.

    .PARAMETER IncludeFile
        Also return the document itself (Bytes).

    .OUTPUTS
        @{ AddonId; Key; FileName; Title; Images; UploadedBy; UploadedAt; Bytes (with -IncludeFile) }, or $null.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$AddonId,
        [Parameter(Mandatory)][string]$Key,
        [switch]$IncludeFile
    )

    if ($AddonId -notmatch '^[a-z0-9][a-z0-9-]{1,38}[a-z0-9]$' -or $Key -notmatch '^[a-z0-9][a-z0-9-]{0,40}$') { return $null }
    $Table = Get-CIPPTable -TableName 'AddonGuides'
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq '$AddonId' and RowKey eq '$Key'" | Select-Object -First 1
    if (-not $Row -or -not $Row.Docx) { return $null }
    $Guide = [ordered]@{
        AddonId    = $AddonId
        Key        = $Key
        FileName   = "$($Row.FileName)"
        Title      = "$($Row.Title)"
        Images     = [int]("0$($Row.Images)")
        UploadedBy = "$($Row.UploadedBy)"
        UploadedAt = "$($Row.UploadedAt)"
    }
    if ($IncludeFile) { $Guide.Bytes = [Convert]::FromBase64String("$($Row.Docx)") }
    [pscustomobject]$Guide
}
