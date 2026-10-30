function Test-CIPPAddonPackage {
    <#
    .SYNOPSIS
        Checks a Community Additions add-on package (.zip) without unpacking it to disk.

    .DESCRIPTION
        A package has addon.json at its root, an optional checksums.json, and one folder per area in
        Config/AddonLayout.json (backend/functions, frontend/pages, ...). This checks:
          - size and file-count limits, and that every path is a plain relative path (no .., no absolute
            paths, no backslashes)
          - every file sits in a known area and has an extension that area allows
          - addon.json is a valid manifest (Test-CIPPAddonManifest)
          - every endpoint listed in addon.json has its backend/endpoints/Invoke-<name>.ps1, and every
            Invoke-*.ps1 there is listed
          - every backend .ps1 file defines the function it is named after, and nothing else at the top level
          - checksums.json, when present, matches every file

        Nothing in a package is run here, or by the add-on manager: an add-on only takes effect once
        installed into the repository with build/tools/addons/Install-CippAddon.ps1, reviewed and built.

        Returns Valid, Errors, Warnings, Manifest, Files (Path, Area, Bytes, Sha256), Sha256 (of the
        whole package) and Bytes.

    .PARAMETER Path
        The package file.

    .PARAMETER Bytes
        The package contents (an upload).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Path')]
    param(
        [Parameter(Mandatory, ParameterSetName = 'Path')][string]$Path,
        [Parameter(Mandatory, ParameterSetName = 'Bytes')][byte[]]$Bytes,
        $Layout
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction SilentlyContinue
    if (-not $Layout) { $Layout = Get-CIPPAddonLayout }
    if ($PSCmdlet.ParameterSetName -eq 'Path') { $Bytes = [System.IO.File]::ReadAllBytes((Resolve-Path -Path $Path).Path) }

    $Errors = [System.Collections.Generic.List[string]]::new()
    $Warnings = [System.Collections.Generic.List[string]]::new()
    $Files = [System.Collections.Generic.List[object]]::new()
    $Manifest = $null
    $Checksums = $null
    $Sha = [System.Security.Cryptography.SHA256]::Create()
    $Hex = { param([byte[]]$B) ([System.BitConverter]::ToString($Sha.ComputeHash($B)) -replace '-').ToLowerInvariant() }
    $Result = {
        [pscustomobject]@{
            Valid    = ($Errors.Count -eq 0)
            Errors   = @($Errors)
            Warnings = @($Warnings)
            Manifest = $Manifest
            Files    = @($Files)
            Sha256   = & $Hex $Bytes
            Bytes    = $Bytes.Length
        }
    }

    if ($Bytes.Length -gt $Layout.limits.packageBytes) {
        $Errors.Add("The package is $([math]::Round($Bytes.Length / 1MB, 1)) MB; the limit is $([math]::Round($Layout.limits.packageBytes / 1MB)) MB.")
        return & $Result
    }

    $Stream = [System.IO.MemoryStream]::new($Bytes)
    try {
        $Zip = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Read)
    } catch {
        $Errors.Add("This isn't a .zip file the add-on manager can read.")
        return & $Result
    }

    try {
        $Entries = @($Zip.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        if ($Entries.Count -gt $Layout.limits.files) {
            $Errors.Add("The package has $($Entries.Count) files; the limit is $($Layout.limits.files).")
            return & $Result
        }
        $Total = ($Entries | Measure-Object -Property Length -Sum).Sum
        if ($Total -gt $Layout.limits.packageBytes) {
            $Errors.Add("The package unpacks to $([math]::Round($Total / 1MB, 1)) MB; the limit is $([math]::Round($Layout.limits.packageBytes / 1MB)) MB.")
            return & $Result
        }

        $Contents = @{}
        foreach ($Entry in $Entries) {
            $Name = $Entry.FullName
            if ($Name -match '\\' -or $Name.StartsWith('/') -or $Name -match '^[A-Za-z]:' -or ($Name -split '/') -contains '..' -or ($Name -split '/') -contains '.' -or $Name -match '//' -or $Name -match '[\x00-\x1f]') {
                $Errors.Add("'$Name' isn't a plain relative path.")
                continue
            }
            if ($Entry.Length -gt $Layout.limits.fileBytes) {
                $Errors.Add("'$Name' is larger than $([math]::Round($Layout.limits.fileBytes / 1MB)) MB.")
                continue
            }
            if ($Contents.ContainsKey($Name.ToLowerInvariant())) { $Errors.Add("'$Name' is in the package twice."); continue }
            $Reader = $Entry.Open()
            try { $Buffer = [System.IO.MemoryStream]::new(); $Reader.CopyTo($Buffer); $Data = $Buffer.ToArray() } finally { $Reader.Dispose() }
            $Contents[$Name.ToLowerInvariant()] = $Data

            if ($Name -eq $Layout.manifest.package) { continue }
            if ($Name -eq 'checksums.json') { continue }
            $Area = $Layout.areas | Where-Object { $Name.StartsWith("$($_.package)/") } | Select-Object -First 1
            if (-not $Area) { $Errors.Add("'$Name' isn't in one of the add-on folders ($(@($Layout.areas.package) -join ', ')).") ; continue }
            $Ext = [System.IO.Path]::GetExtension($Name).ToLowerInvariant()
            if ($Area.extensions -notcontains $Ext) { $Errors.Add("'$Name': $($Area.label) can only be $($Area.extensions -join ', ') files."); continue }
            $Files.Add([pscustomobject]@{ Path = $Name; Area = $Area.package; Bytes = $Data.Length; Sha256 = & $Hex $Data })
        }

        $ManifestBytes = $Contents[$Layout.manifest.package]
        if (-not $ManifestBytes) {
            $Errors.Add("There's no $($Layout.manifest.package) at the top of the package.")
            return & $Result
        }
        try {
            $Manifest = [System.Text.Encoding]::UTF8.GetString($ManifestBytes).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
        } catch {
            $Errors.Add("$($Layout.manifest.package) isn't valid JSON.")
            return & $Result
        }
        foreach ($P in @(Test-CIPPAddonManifest -Manifest $Manifest)) { $Errors.Add($P) }

        # Endpoints: listed ones exist, existing ones are listed.
        $EndpointFiles = @($Files | Where-Object { $_.Area -eq 'backend/endpoints' } | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Path) })
        foreach ($E in @($Manifest.endpoints | Where-Object { $_ })) {
            if ($EndpointFiles -notcontains "Invoke-$E") { $Errors.Add("addon.json lists the endpoint $E but there's no backend/endpoints/Invoke-$E.ps1.") }
        }
        foreach ($F in $EndpointFiles) {
            if ($F -notmatch '^Invoke-') { $Errors.Add("backend/endpoints/$F.ps1: endpoint files are named Invoke-<Endpoint>.ps1."); continue }
            if (@($Manifest.endpoints) -notcontains ($F -replace '^Invoke-')) { $Errors.Add("$F.ps1 isn't listed under endpoints in addon.json, so it couldn't be turned off with the add-on.") }
        }

        # Backend scripts: one function per file, named after the file, nothing else at the top level.
        foreach ($F in @($Files | Where-Object { $_.Area -in 'backend/functions', 'backend/endpoints' })) {
            $Text = [System.Text.Encoding]::UTF8.GetString($Contents[$F.Path.ToLowerInvariant()]).TrimStart([char]0xFEFF)
            $Tokens = $null; $ParseErrors = $null
            $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$Tokens, [ref]$ParseErrors)
            if ($ParseErrors.Count -gt 0) { $Errors.Add("$($F.Path) doesn't parse: $($ParseErrors[0].Message)"); continue }
            $Expected = [System.IO.Path]::GetFileNameWithoutExtension($F.Path)
            $Top = @($Ast.EndBlock.Statements) + @($Ast.BeginBlock.Statements) + @($Ast.ProcessBlock.Statements) | Where-Object { $_ }
            $Functions = @($Top | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })
            if ($Functions.Count -ne 1 -or $Functions[0].Name -ne $Expected) { $Errors.Add("$($F.Path) must define exactly one function, $Expected.") }
            if ($Top.Count -ne $Functions.Count) { $Errors.Add("$($F.Path) has code outside its function; it would run when CIPP loads.") }
        }

        # Pages: Next.js pages under /addons/<id>.
        if (@($Files | Where-Object { $_.Area -eq 'frontend/pages' }).Count -eq 0) { $Warnings.Add('The package has no pages (frontend/pages).') }
        $MenuPaths = @($Manifest.menu | Where-Object { $_.path } | ForEach-Object { $_.path })
        foreach ($MenuPath in $MenuPaths) {
            $Rel = $MenuPath -replace "^/addons/$([regex]::Escape("$($Manifest.id)"))", ''
            $Candidates = if ($Rel) { @("frontend/pages$Rel.jsx", "frontend/pages$Rel.js", "frontend/pages$Rel/index.jsx", "frontend/pages$Rel/index.js") } else { @('frontend/pages/index.jsx', 'frontend/pages/index.js') }
            if (-not ($Candidates | Where-Object { $Contents.ContainsKey($_.ToLowerInvariant()) })) { $Errors.Add("The menu entry $MenuPath has no page in frontend/pages.") }
        }
        if (@($Files | Where-Object { $_.Area -in 'backend/tests', 'frontend/tests' }).Count -eq 0) { $Warnings.Add('The package has no tests.') }
        if (@($Files | Where-Object { $_.Area -eq 'docs' }).Count -eq 0) { $Warnings.Add('The package has no documentation (docs).') }

        # Checksums.
        if ($Contents.ContainsKey('checksums.json')) {
            try {
                $Checksums = [System.Text.Encoding]::UTF8.GetString($Contents['checksums.json']).TrimStart([char]0xFEFF) | ConvertFrom-Json -ErrorAction Stop
                $Listed = @{}
                foreach ($P in $Checksums.files.PSObject.Properties) { $Listed[$P.Name.ToLowerInvariant()] = "$($P.Value)".ToLowerInvariant() }
                foreach ($Key in $Contents.Keys) {
                    if ($Key -eq 'checksums.json') { continue }
                    if (-not $Listed.ContainsKey($Key)) { $Errors.Add("checksums.json doesn't list '$Key'."); continue }
                    if ($Listed[$Key] -ne (& $Hex $Contents[$Key])) { $Errors.Add("'$Key' doesn't match its checksum; the package has been changed since it was made.") }
                }
                foreach ($Key in $Listed.Keys) { if (-not $Contents.ContainsKey($Key)) { $Errors.Add("checksums.json lists '$Key', which isn't in the package.") } }
            } catch {
                $Errors.Add("checksums.json isn't valid JSON.")
            }
        } else {
            $Warnings.Add('The package has no checksums.json, so changes to it since it was made can''t be detected.')
        }
    } finally {
        $Zip.Dispose()
        $Stream.Dispose()
    }
    $Out = & $Result
    if ($Checksums) {
        $Out | Add-Member -NotePropertyName PackagedAt -NotePropertyValue $Checksums.packagedAt
        $Out | Add-Member -NotePropertyName PackagedOn -NotePropertyValue $Checksums.packagedOn
    }
    $Out
}
