function ConvertFrom-CIPPDocxGuide {
    <#
    .SYNOPSIS
        Turns a simple Word (.docx) how-to guide into report components, so it can be added to a CIPP PDF
        in the PDF's own style.

    .DESCRIPTION
        Made for an MSP's own client guides (for example "Connecting Claude to Microsoft 365"), which are
        stored in the instance rather than the code. Handles what such guides use:

        - The opening lines: a short all-capitals label is dropped, the next line is the title and the
          one after it (if short) the subtitle; the PDF shows them as the page title.
        - Headings (Heading/Title styles, or a short all-bold line) and numbered steps ("1  Open
          Settings") become section headings.
        - Paragraphs keep bold and italic. Bulleted and numbered lists become bullet lists.
        - Pictures become images at their size in the document; pictures side by side in a table become
          a row of images.
        - A one-cell table (a boxed note) becomes a callout: its first line is the title, and a title
          with "important", "warning" or "note" in it is shown as a warning.
        - Other tables become tables, with the first row as the header.

        Headers, footers and comments are ignored.

    .PARAMETER Bytes
        The .docx file.

    .OUTPUTS
        @{ Title; Subtitle; Blocks; Images (count) }

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][byte[]]$Bytes)

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    $Stream = [System.IO.MemoryStream]::new($Bytes)
    try { $Zip = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Read) }
    catch { throw 'That file is not a Word document (.docx).' }

    $ReadEntry = {
        param($Name)
        $E = $Zip.GetEntry($Name)
        if (-not $E) { return $null }
        $S = $E.Open(); $M = [System.IO.MemoryStream]::new()
        try { $S.CopyTo($M) } finally { $S.Dispose() }
        , $M.ToArray()
    }
    $ReadText = { param($Name) $B = & $ReadEntry $Name; if ($null -eq $B) { $null } else { [System.Text.Encoding]::UTF8.GetString($B) } }

    $DocXml = & $ReadText 'word/document.xml'
    if (-not $DocXml) { $Zip.Dispose(); throw 'That file is not a Word document (.docx).' }
    $Doc = [xml]$DocXml
    $Ns = [System.Xml.XmlNamespaceManager]::new($Doc.NameTable)
    $Ns.AddNamespace('w', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main')
    $Ns.AddNamespace('a', 'http://schemas.openxmlformats.org/drawingml/2006/main')
    $Ns.AddNamespace('r', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships')
    $Ns.AddNamespace('wp', 'http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing')

    # Picture relationships: rId -> data URL.
    $Rels = @{}
    $RelXml = & $ReadText 'word/_rels/document.xml.rels'
    if ($RelXml) {
        foreach ($Rel in ([xml]$RelXml).Relationships.Relationship) {
            if ("$($Rel.Type)" -notmatch '/image$') { continue }
            $Path = 'word/' + ("$($Rel.Target)" -replace '^/word/', '' -replace '^\./', '')
            $ImgBytes = & $ReadEntry $Path
            if ($null -eq $ImgBytes) { continue }
            $Ext = [System.IO.Path]::GetExtension($Path).TrimStart('.').ToLowerInvariant()
            $Mime = switch ($Ext) { 'jpg' { 'image/jpeg' } 'jpeg' { 'image/jpeg' } 'gif' { 'image/gif' } 'bmp' { 'image/bmp' } 'png' { 'image/png' } default { $null } }
            if ($Mime) { $Rels["$($Rel.Id)"] = "data:$Mime;base64,$([Convert]::ToBase64String($ImgBytes))" }
        }
    }
    $Zip.Dispose()

    $Enc = { param($T) [System.Net.WebUtility]::HtmlEncode([string]$T) }
    $On = { param($Node) $Node -and "$($Node.GetAttribute('val', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'))" -notin @('0', 'false', 'off') }

    # One paragraph: its runs (text, bold, italic), pictures, style and whether it is a list item.
    $ReadParagraph = {
        param($P)
        $Runs = [System.Collections.Generic.List[object]]::new()
        $Images = [System.Collections.Generic.List[object]]::new()
        foreach ($R in $P.SelectNodes('.//w:r', $Ns)) {
            $Bold = & $On ($R.SelectSingleNode('w:rPr/w:b', $Ns))
            $Italic = & $On ($R.SelectSingleNode('w:rPr/w:i', $Ns))
            foreach ($C in $R.ChildNodes) {
                switch ($C.LocalName) {
                    't' { $Runs.Add([pscustomobject]@{ Text = $C.InnerText; Bold = $Bold; Italic = $Italic }) }
                    'tab' { $Runs.Add([pscustomobject]@{ Text = ' '; Bold = $false; Italic = $false }) }
                    'br' { $Runs.Add([pscustomobject]@{ Text = "`n"; Bold = $false; Italic = $false }) }
                    'drawing' {
                        $Blip = $C.SelectSingleNode('.//a:blip', $Ns)
                        $Id = if ($Blip) { $Blip.GetAttribute('embed', 'http://schemas.openxmlformats.org/officeDocument/2006/relationships') }
                        $Extent = $C.SelectSingleNode('.//wp:extent', $Ns)
                        $WidthPt = if ($Extent) { [math]::Round([double]$Extent.GetAttribute('cx') / 12700, 1) } else { $null }
                        if ($Id -and $Rels.ContainsKey($Id)) { $Images.Add([pscustomobject]@{ Data = $Rels[$Id]; Width = $WidthPt }) }
                    }
                }
            }
        }
        $Plain = (-join ($Runs | ForEach-Object { $_.Text })) -replace [char]0x00A0, ' '
        $StyleNode = $P.SelectSingleNode('w:pPr/w:pStyle', $Ns)
        $Style = if ($StyleNode) { "$($StyleNode.GetAttribute('val', 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'))" } else { '' }
        $TextRuns = @($Runs | Where-Object { $_.Text.Trim() })
        [pscustomobject]@{
            Runs    = @($Runs)
            Plain   = $Plain.Trim()
            Images  = @($Images)
            Style   = $Style
            List    = [bool]$P.SelectSingleNode('w:pPr/w:numPr', $Ns)
            AllBold = ($TextRuns.Count -gt 0 -and -not ($TextRuns | Where-Object { -not $_.Bold }))
        }
    }
    # Runs as HTML (paragraphs) or markdown (bullets and callouts), with bold and italic kept.
    $AsHtml = {
        param($Info)
        (-join ($Info.Runs | ForEach-Object {
                    $T = (& $Enc ($_.Text -replace [char]0x00A0, ' ')) -replace "`n", '<br/>'
                    if (-not $_.Text.Trim()) { $T } elseif ($_.Bold -and $_.Italic) { "<b><i>$T</i></b>" } elseif ($_.Bold) { "<b>$T</b>" } elseif ($_.Italic) { "<i>$T</i>" } else { $T }
                })).Trim()
    }
    $AsMarkdown = {
        param($Info)
        $Out = -join ($Info.Runs | ForEach-Object {
                $T = ($_.Text -replace [char]0x00A0, ' ') -replace '([*_])', '\$1'
                if (-not $T.Trim()) { $T } elseif ($_.Bold) { $Lead = $T -replace '^(\s*).*$', '$1'; $Trail = $T -replace '^.*?(\s*)$', '$1'; "$Lead**$($T.Trim())**$Trail" } elseif ($_.Italic) { "*$($T.Trim())*" } else { $T }
            })
        ($Out -replace '\*\*\s*\*\*', '').Trim()
    }

    $Blocks = [System.Collections.Generic.List[object]]::new()
    $Bullets = [System.Collections.Generic.List[object]]::new()
    $FlushBullets = { if ($Bullets.Count -gt 0) { $Blocks.Add((New-CippReportBullets -Items @($Bullets))); $Bullets.Clear() } }
    $AddImages = {
        param($Images)
        foreach ($I in $Images) {
            $Node = [ordered]@{ type = 'image'; image = $I.Data }
            if ($I.Width) { $Node.width = [double]$I.Width }
            $Blocks.Add($Node)
        }
    }
    $Title = $null; $Subtitle = $null; $Opening = $true; $ImageCount = 0
    $Body = $Doc.SelectSingleNode('/w:document/w:body', $Ns)

    foreach ($Node in $Body.ChildNodes) {
        if ($Node.LocalName -eq 'p') {
            $Info = & $ReadParagraph $Node
            $ImageCount += $Info.Images.Count
            if (-not $Info.Plain -and $Info.Images.Count -eq 0) { continue }

            # Opening lines: label (all capitals), title, subtitle.
            if ($Opening -and $Info.Images.Count -eq 0 -and -not $Info.List) {
                if (-not $Title -and $Info.Plain.Length -le 40 -and $Info.Plain -cmatch '^[^a-z]*[A-Z][^a-z]*$') { continue }
                if (-not $Title) { $Title = $Info.Plain; continue }
                if (-not $Subtitle -and $Info.Plain.Length -le 200 -and $Info.Style -notmatch '^Heading') { $Subtitle = $Info.Plain; $Opening = $false; continue }
            }
            $Opening = $false

            if ($Info.List) { $Bullets.Add(@{ text = (& $AsMarkdown $Info) }); continue }
            & $FlushBullets

            if ($Info.Plain) {
                if ($Info.Plain -match '^\s*(\d{1,2})\s+(\S.*)$' -and $Info.AllBold) {
                    $Blocks.Add((New-CippReportHeading -Title "$($Matches[1]). $($Matches[2].Trim())"))
                } elseif ($Info.Style -match '^(Heading\d|Title|Subtitle)$' -or ($Info.AllBold -and $Info.Plain.Length -le 80)) {
                    $Blocks.Add((New-CippReportHeading -Title $Info.Plain))
                } else {
                    $Blocks.Add((New-CippReportParagraph -Html "<p>$(& $AsHtml $Info)</p>"))
                }
            }
            & $AddImages $Info.Images
        } elseif ($Node.LocalName -eq 'tbl') {
            & $FlushBullets
            $Opening = $false
            $RowsXml = @($Node.SelectNodes('w:tr', $Ns))
            $Cells = @($Node.SelectNodes('w:tr/w:tc', $Ns))
            $CellInfo = @($Cells | ForEach-Object { , @($_.SelectNodes('.//w:p', $Ns) | ForEach-Object { & $ReadParagraph $_ }) })
            $AllImages = @($CellInfo | ForEach-Object { $_ } | ForEach-Object { $_.Images } | Where-Object { $_ })
            $AnyText = [bool](@($CellInfo | ForEach-Object { $_ } | Where-Object { $_.Plain }))
            $ImageCount += $AllImages.Count

            if (-not $AnyText -and $AllImages.Count -gt 0) {
                # Pictures side by side.
                if ($AllImages.Count -eq 1) { & $AddImages $AllImages }
                else { $Blocks.Add([ordered]@{ type = 'imagerow'; images = @($AllImages | ForEach-Object { $N = [ordered]@{ image = $_.Data }; if ($_.Width) { $N.width = "$($_.Width)" }; $N }) }) }
            } elseif ($Cells.Count -eq 1) {
                # A boxed note: first line the title, the rest the body.
                $Lines = @($CellInfo[0] | Where-Object { $_.Plain })
                $BoxTitle = if ($Lines.Count -gt 0) { $Lines[0].Plain } else { '' }
                $BoxBody = @($Lines | Select-Object -Skip 1 | ForEach-Object { if ($_.List) { "$([char]0x2022) $(& $AsMarkdown $_)" } else { & $AsMarkdown $_ } }) -join "`n"
                if ($BoxTitle -match '(?i)important|warning|caution|note') {
                    $Blocks.Add((New-CippReportInfoBox -Title $BoxTitle -Tone warn -Lines -Content $BoxBody))
                } else {
                    $Blocks.Add((New-CippReportInfoBox -Title $BoxTitle -Lines -Content $BoxBody))
                }
                & $AddImages @($CellInfo[0] | ForEach-Object { $_.Images } | Where-Object { $_ })
            } else {
                # A table: first row as the header.
                $Grid = @($RowsXml | ForEach-Object { , @($_.SelectNodes('w:tc', $Ns) | ForEach-Object { (@($_.SelectNodes('.//w:p', $Ns) | ForEach-Object { (& $ReadParagraph $_).Plain } | Where-Object { $_ }) -join ' ') }) })
                if ($Grid.Count -gt 0) {
                    $Header = @($Grid[0])
                    $Columns = for ($i = 0; $i -lt $Header.Count; $i++) { @{ header = $(if ($Header[$i]) { $Header[$i] } else { ' ' }); key = "c$i" } }
                    $Rows = @($Grid | Select-Object -Skip 1 | ForEach-Object { $R = $_; $H = @{}; for ($i = 0; $i -lt $Header.Count; $i++) { $H["c$i"] = if ($i -lt $R.Count) { $R[$i] } else { '' } }; $H })
                    $Blocks.Add((New-CippReportTable -Columns @($Columns) -Rows $Rows -Limit 200))
                }
                & $AddImages $AllImages
            }
        }
    }
    & $FlushBullets

    if (-not $Title) { $Title = 'Guide' }
    [pscustomobject]@{ Title = $Title; Subtitle = $Subtitle; Blocks = @($Blocks); Images = $ImageCount }
}
