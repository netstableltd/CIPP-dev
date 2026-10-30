<#
.SYNOPSIS
    Checks the installed add-ons against another CIPP version before you merge it.

.DESCRIPTION
    Run it after fetching upstream and before merging, for example:

        git fetch upstream --tags
        pwsh build/tools/addons/Test-CippAddonUpstream.ps1 -Ref upstream/main

    For each add-on it reports:
      BREAK   something the add-on uses (dependsOn) is gone in -Ref, or -Ref adds a function or endpoint
              with the same name as one of the add-on's
              or a CIPP function it calls lost a parameter
      REVIEW  a CIPP function or frontend file the add-on uses changed between -Base and -Ref, or a core
              file the add-on changed (coreChanges) changed upstream too (expect a merge conflict)
      OK      nothing it uses changed

    and whether the add-on has been tested with -Ref's CIPP version. Exits 1 when anything breaks.

.PARAMETER Ref
    The CIPP to check against (a branch, tag or commit): upstream/main, v11.3.0 ...

.PARAMETER Base
    What the add-ons were last checked on (default: the merge base of HEAD and -Ref).
#>
[CmdletBinding()]
param(
    [string]$Ref = 'upstream/main',
    [string]$Base
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'AddonTools.ps1')
Push-Location $RepoRoot
try {
    git rev-parse --verify --quiet "$Ref^{commit}" | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Can't find '$Ref'. Fetch it first (git fetch upstream --tags)." }
    if (-not $Base) { $Base = (git merge-base HEAD $Ref).Trim() }
    $RefFiles = [System.Collections.Generic.HashSet[string]]::new([string[]]@(git ls-tree -r --name-only $Ref))
    $Changed = [System.Collections.Generic.HashSet[string]]::new([string[]]@(git diff --name-only $Base $Ref))
    $RefVersion = ((git show "$($Ref):backend/version_latest.txt") -join '').Trim()
    $Layout = Get-AddonToolLayout
    $CoreIndex = Get-AddonCoreFunctionIndex
    # Functions in -Ref, by file name (outside add-on folders).
    $RefFunctions = @{}
    foreach ($Line in @(git grep -I -E '^\s*[Ff]unction\s+[A-Za-z][A-Za-z0-9_-]*' $Ref -- 'backend/Modules')) {
        # <ref>:<path>:<text>
        if (-not $Line.StartsWith("$($Ref):")) { continue }
        if ($Line.Substring($Ref.Length + 1) -notmatch '^(?<file>[^:]+\.ps1):\s*function\s+(?<name>[\w-]+)') { continue }
        if ($Matches.file -match '/Addons/') { continue }
        if (-not $RefFunctions.ContainsKey($Matches.name)) { $RefFunctions[$Matches.name] = $Matches.file }
    }
    $AnyBreak = $false
    function Get-FunctionParameters([string]$Commit, [string]$File, [string]$Name) {
        $Text = (git show "$($Commit):$File" 2>$null) -join "`n"
        if (-not $Text) { return @() }
        $Ast = [System.Management.Automation.Language.Parser]::ParseInput($Text, [ref]$null, [ref]$null)
        $Def = $Ast.Find({ param($N) $N -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $N.Name -eq $Name }, $true)
        if (-not $Def) { return @() }
        @($Def.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) + @($Def.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath }) | Where-Object { $_ }
    }

    foreach ($Dir in Get-ChildItem (Join-Path $RepoRoot 'backend/Config/Addons') -Directory) {
        $ManifestPath = Join-Path $Dir.FullName 'addon.json'
        if (-not (Test-Path $ManifestPath)) { continue }
        $M = Get-Content $ManifestPath -Raw | ConvertFrom-Json
        $Findings = [System.Collections.Generic.List[object]]::new()
        $Add = { param($Level, $What) $Findings.Add([pscustomobject]@{ Level = $Level; What = $What }) }

        foreach ($Fn in @($M.dependsOn.functions)) {
            $Here = $CoreIndex[$Fn]
            if (-not $RefFunctions.ContainsKey($Fn)) { & $Add 'BREAK' "CIPP function $Fn is gone (was $Here)." ; continue }
            $There = $RefFunctions[$Fn]
            if ($Here -and $Here -ne $There) { & $Add 'REVIEW' "CIPP function $Fn moved: $Here -> $There." }
            elseif ($Changed.Contains($There)) {
                $Stat = (git diff --shortstat $Base $Ref -- $There).Trim()
                $Before = Get-FunctionParameters -Commit $Base -File $There -Name $Fn
                $After = Get-FunctionParameters -Commit $Ref -File $There -Name $Fn
                $Removed = @($Before | Where-Object { $After -notcontains $_ })
                $Added = @($After | Where-Object { $Before -notcontains $_ })
                if ($Removed.Count) {
                    & $Add 'BREAK' "CIPP function $Fn lost parameters: $($Removed -join ', ')$(if ($Added.Count) { "; gained $($Added -join ', ')" }). Check every call to it in the add-on."
                } elseif ($Added.Count) {
                    & $Add 'REVIEW' "CIPP function $Fn gained parameters ($($Added -join ', ')), $Stat. Existing calls should still work; check any new mandatory ones."
                } else {
                    & $Add 'REVIEW' "CIPP function $Fn changed inside ($Stat), same parameters. Check its output still suits the add-on."
                }
            }
        }
        foreach ($Spec in @($M.dependsOn.frontend)) {
            $File = Resolve-AddonFrontendFile -Spec $Spec -Exists { param($P) $RefFiles.Contains($P) }
            if (-not $File) { & $Add 'BREAK' "Frontend file $Spec is gone."; continue }
            if ($Changed.Contains($File)) { & $Add 'REVIEW' "Frontend file $File changed ($((git diff --shortstat $Base $Ref -- $File).Trim())). Check the props and exports the add-on uses." }
        }
        foreach ($Core in @($M.coreChanges)) {
            foreach ($File in @($Core.files)) {
                if (-not $RefFiles.Contains($File)) { & $Add 'BREAK' "Core file $File, which the add-on changes ($($Core.area)), is gone." }
                elseif ($Changed.Contains($File)) { & $Add 'REVIEW' "Core file $File, which the add-on changes ($($Core.area)), changed upstream too: expect a merge conflict." }
            }
        }
        # Name clashes: upstream adding something with the add-on's names.
        $OwnNames = @()
        foreach ($Area in $Layout.areas | Where-Object { $_.package -in 'backend/functions', 'backend/endpoints' }) {
            $Folder = Get-AddonRepoPath -Template $Area.repo -Id $M.id
            if (Test-Path $Folder) { $OwnNames += @(Get-ChildItem $Folder -Filter '*.ps1' -Recurse | ForEach-Object { $_.BaseName }) }
        }
        foreach ($N in $OwnNames) { if ($RefFunctions.ContainsKey($N)) { & $Add 'BREAK' "Upstream now has its own $N ($($RefFunctions[$N])); the add-on's would clash." } }
        foreach ($Item in @($M.menu)) {
            $Page = "frontend/src/pages$($Item.path)"
            if ($RefFiles.Contains("$Page.jsx") -or $RefFiles.Contains("$Page/index.jsx")) { & $Add 'BREAK' "Upstream now has a page at $($Item.path)." }
        }

        $Tested = @($M.cipp.testedWith) | Where-Object { (($_ -split '\.')[0..1] -join '.') -eq (($RefVersion -split '\.')[0..1] -join '.') }
        $Worst = if ($Findings.Level -contains 'BREAK') { 'BREAK' } elseif ($Findings.Level -contains 'REVIEW') { 'REVIEW' } else { 'OK' }
        if ($Worst -eq 'BREAK') { $AnyBreak = $true }
        $Colour = @{ BREAK = 'Red'; REVIEW = 'Yellow'; OK = 'Green' }[$Worst]
        Write-Host ''
        Write-Host "$($M.name) $($M.version) [$($M.id)]: $Worst" -ForegroundColor $Colour
        Write-Host ("  CIPP {0}: {1}" -f $RefVersion, $(if ($Tested) { 'tested' } else { "not tested yet (tested with $(@($M.cipp.testedWith) -join ', '))" }))
        foreach ($F in $Findings) { Write-Host "  $($F.Level.PadRight(6)) $($F.What)" -ForegroundColor @{ BREAK = 'Red'; REVIEW = 'Yellow' }[$F.Level] }
        if ($Findings.Count -eq 0) { Write-Host '  Nothing it uses from CIPP changed.' }
    }
    Write-Host ''
    Write-Host "Compared $((git rev-parse --short $Base).Trim()) -> $Ref ($((git rev-parse --short $Ref).Trim()), CIPP $RefVersion)."
    Write-Host 'After merging and testing, add the new version to cipp.testedWith in each add-on that works.'
    if ($AnyBreak) { exit 1 }
} finally { Pop-Location }
