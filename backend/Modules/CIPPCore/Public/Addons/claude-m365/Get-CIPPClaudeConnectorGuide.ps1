function Get-CIPPClaudeConnectorGuide {
    <#
    .SYNOPSIS
        The connection guide uploaded for Claude for Microsoft 365 (a Word document), if there is one.

    .DESCRIPTION
        The guide is the MSP's own document, kept in this CIPP instance (table CommunityProcesses,
        ClaudeM365 / Guide) rather than in the code, and added to the end of the setup summary PDF.
        Returns $null when none has been uploaded.

    .PARAMETER IncludeFile
        Also return the document itself (Bytes).

    .OUTPUTS
        @{ FileName; Title; Images; UploadedBy; UploadedAt; Bytes (with -IncludeFile) }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$IncludeFile)

    $Table = Get-CIPPTable -TableName 'CommunityProcesses'
    $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'ClaudeM365' and RowKey eq 'Guide'" | Select-Object -First 1
    if (-not $Row -or -not $Row.Docx) { return $null }
    $Guide = [ordered]@{
        FileName   = "$($Row.FileName)"
        Title      = "$($Row.Title)"
        Images     = [int]("0$($Row.Images)")
        UploadedBy = "$($Row.UploadedBy)"
        UploadedAt = "$($Row.UploadedAt)"
    }
    if ($IncludeFile) { $Guide.Bytes = [Convert]::FromBase64String("$($Row.Docx)") }
    [pscustomobject]$Guide
}
