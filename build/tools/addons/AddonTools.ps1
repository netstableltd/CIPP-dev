# Shared by the add-on package tools. Loads the add-on manager functions straight from the CIPPCore
# source, so the tools and the running CIPP check packages the same way.
$script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '../../..')).Path
foreach ($F in Get-ChildItem -Path (Join-Path $script:RepoRoot 'backend/Modules/CIPPCore/Public/AddonManager') -Filter '*.ps1') { . $F.FullName }

function Get-AddonToolLayout {
    param([string]$RepoRoot = $script:RepoRoot)
    Get-Content -Path (Join-Path $RepoRoot 'backend/Config/AddonLayout.json') -Raw | ConvertFrom-Json
}

function Get-AddonRepoPath {
    # Repository folder (or the manifest file) for an add-on area.
    param([string]$Template, [string]$Id, [string]$RepoRoot = $script:RepoRoot)
    Join-Path $RepoRoot ($Template -replace '\{id\}', $Id)
}

function Get-AddonRepoVersion {
    param([string]$RepoRoot = $script:RepoRoot)
    $Text = (Get-Content -Path (Join-Path $RepoRoot 'backend/version_latest.txt') -Raw).Trim()
    if ($Text -match '^v?(\d+\.\d+\.\d+)') { $Matches[1] } else { $Text }
}

function Get-AddonCoreFunctionIndex {
    # CIPP's own functions: name -> repository path, for every backend .ps1 outside the add-on folders.
    # CIPP keeps one function per file, named after the file.
    param([string]$RepoRoot = $script:RepoRoot)
    # Mostly one function per file named after it, but some files hold several (New-CippReportComponents.ps1),
    # so the function definitions themselves are read.
    $Index = @{}
    foreach ($F in Get-ChildItem -Path (Join-Path $RepoRoot 'backend/Modules') -Filter '*.ps1' -Recurse) {
        $Rel = [System.IO.Path]::GetRelativePath($RepoRoot, $F.FullName) -replace '\\', '/'
        if ($Rel -match '/Addons/') { continue }
        foreach ($M in [regex]::Matches([System.IO.File]::ReadAllText($F.FullName), '(?im)^\s*function\s+([\w-]+)')) {
            if (-not $Index.ContainsKey($M.Groups[1].Value)) { $Index[$M.Groups[1].Value] = $Rel }
        }
    }
    $Index
}

function Get-AddonDependencies {
    <#
        What an add-on uses from CIPP itself: the CIPP functions its backend code calls, and the
        frontend files it imports from outside its own folders (as src/... without the extension).
    #>
    param([Parameter(Mandatory)][string]$Id, [string]$RepoRoot = $script:RepoRoot, $Layout = (Get-AddonToolLayout -RepoRoot $RepoRoot), $CoreIndex)
    if (-not $CoreIndex) { $CoreIndex = Get-AddonCoreFunctionIndex -RepoRoot $RepoRoot }
    $Own = @{}
    $Functions = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    $Frontend = [System.Collections.Generic.SortedSet[string]]::new([System.StringComparer]::Ordinal)
    $Src = Join-Path $RepoRoot 'frontend/src'
    $OwnFrontend = @('frontend/src/addons/{id}', 'frontend/src/pages/addons/{id}') | ForEach-Object { [System.IO.Path]::GetFullPath((Get-AddonRepoPath -Template $_ -Id $Id -RepoRoot $RepoRoot)) }

    foreach ($Area in $Layout.areas | Where-Object { $_.package -in 'backend/functions', 'backend/endpoints' }) {
        $Folder = Get-AddonRepoPath -Template $Area.repo -Id $Id -RepoRoot $RepoRoot
        if (Test-Path $Folder) { Get-ChildItem $Folder -Filter '*.ps1' -Recurse | ForEach-Object { $Own[$_.BaseName] = $true } }
    }
    foreach ($Area in $Layout.areas | Where-Object { $_.package -in 'backend/functions', 'backend/endpoints' }) {
        $Folder = Get-AddonRepoPath -Template $Area.repo -Id $Id -RepoRoot $RepoRoot
        if (-not (Test-Path $Folder)) { continue }
        foreach ($F in Get-ChildItem $Folder -Filter '*.ps1' -Recurse) {
            $Ast = [System.Management.Automation.Language.Parser]::ParseFile($F.FullName, [ref]$null, [ref]$null)
            foreach ($Cmd in $Ast.FindAll({ param($N) $N -is [System.Management.Automation.Language.CommandAst] }, $true)) {
                $Name = $Cmd.GetCommandName()
                if ($Name -and -not $Own.ContainsKey($Name) -and $CoreIndex.ContainsKey($Name)) { [void]$Functions.Add($Name) }
            }
        }
    }
    foreach ($Area in $Layout.areas | Where-Object { $_.package -in 'frontend/components', 'frontend/pages' }) {
        $Folder = Get-AddonRepoPath -Template $Area.repo -Id $Id -RepoRoot $RepoRoot
        if (-not (Test-Path $Folder)) { continue }
        foreach ($F in Get-ChildItem $Folder -Include '*.js', '*.jsx' -Recurse) {
            $Text = Get-Content $F.FullName -Raw
            foreach ($M in [regex]::Matches($Text, "(?:from|import)\s+['""]([^'""]+)['""]")) {
                $Spec = $M.Groups[1].Value
                $Target = if ($Spec.StartsWith('.')) { [System.IO.Path]::GetFullPath((Join-Path $F.DirectoryName $Spec)) }
                elseif ($Spec.StartsWith('src/') -or $Spec.StartsWith('/src/')) { [System.IO.Path]::GetFullPath((Join-Path (Join-Path $RepoRoot 'frontend') $Spec.TrimStart('/'))) }
                else { $null }
                if (-not $Target) { continue }
                if ($OwnFrontend | Where-Object { $Target.StartsWith($_) }) { continue }
                $Rel = ('src/' + [System.IO.Path]::GetRelativePath($Src, $Target)) -replace '\\', '/' -replace '\.(jsx?|json)$', ''
                [void]$Frontend.Add($Rel)
            }
        }
    }
    [pscustomobject]@{ functions = @($Functions); frontend = @($Frontend) }
}

function Resolve-AddonFrontendFile {
    # src/components/Foo -> the file it means (Foo.jsx, Foo.js, Foo/index.jsx ...), relative to the repo.
    param([string]$Spec, [scriptblock]$Exists)
    foreach ($Suffix in '', '.jsx', '.js', '.json', '/index.jsx', '/index.js') {
        $Candidate = "frontend/$Spec$Suffix"
        if (& $Exists $Candidate) { return $Candidate }
    }
    $null
}
