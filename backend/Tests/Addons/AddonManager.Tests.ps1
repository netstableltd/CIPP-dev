# Pester tests for the Community Additions add-on system: manifests, version comparison, compatibility,
# package checks, the per-add-on feature flags and the manager endpoints. The last Describe is a guard over
# every add-on installed in this repository, so an upstream merge or an add-on change that breaks one fails
# the tests: its manifest, its package, its dependsOn list against its code, and the CIPP functions and
# frontend files it needs.
#
# Packages here are synthetic, built in-test.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath))   # backend
    $script:Root = Split-Path -Parent $RepoRoot                                               # repository
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [string]$ContentType
        [hashtable]$Headers
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function Get-CIPPTable { param($TableName) @{ Context = $TableName } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Saved.Add([pscustomobject]$Entity) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) @($script:Saved | Where-Object { $Filter -match "PartitionKey eq '$($_.PartitionKey)'" -and (-not ($Filter -match "RowKey eq '([^']+)'") -or $_.RowKey -eq $Matches[1]) }) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Removed.Add($Entity); $null = $script:Saved.Remove($Entity) }
    function Invoke-CIPPRestMethod { param($Uri) throw 'offline' }
    function Set-CIPPFeatureFlag { param($Id, $Enabled) $script:FlagSet = @{ Id = $Id; Enabled = $Enabled }; $true }

    foreach ($F in Get-ChildItem -Path (Join-Path $RepoRoot 'Modules/CIPPCore/Public/AddonManager') -Filter '*.ps1') { . $F.FullName }
    . (& $Find 'Get-CIPPFeatureFlag.ps1')
    foreach ($Name in 'Invoke-ListAddons', 'Invoke-ExecAddon', 'Invoke-ExecAddonDownload') { . (& $Find "$Name.ps1") }
    $env:CIPPRootPath = $RepoRoot
    Add-Type -AssemblyName System.IO.Compression

    $script:Layout = Get-CIPPAddonLayout
    $script:Sha = [System.Security.Cryptography.SHA256]::Create()
    $script:Hex = { param([byte[]]$B) ([System.BitConverter]::ToString($script:Sha.ComputeHash($B)) -replace '-').ToLowerInvariant() }

    $script:GoodManifest = {
        [ordered]@{
            schema = 1; id = 'demo-addon'; name = 'Demo'; version = '1.0.0'; description = 'A demo.'
            cipp = [ordered]@{ minVersion = '11.0.0'; testedWith = @('11.2.1') }
            menu = @([ordered]@{ title = 'Demo'; path = '/addons/demo-addon'; permissions = @('CIPP.Core.*') })
            endpoints = @('ExecDemoAddon')
        }
    }
    $script:GoodFiles = {
        [ordered]@{
            'backend/functions/Get-CIPPDemoThing.ps1' = "function Get-CIPPDemoThing {`n    'thing'`n}`n"
            'backend/endpoints/Invoke-ExecDemoAddon.ps1' = "function Invoke-ExecDemoAddon {`n    param(`$Request)`n    Get-CIPPDemoThing`n}`n"
            'frontend/pages/index.jsx'                = "const Page = () => null`nexport default Page`n"
            'backend/tests/Demo.Tests.ps1'            = "Describe 'demo' { It 'works' { 1 | Should -Be 1 } }`n"
            'docs/README.md'                          = "# Demo`n"
        }
    }
    # Builds a package in memory. -Checksums adds checksums.json over the files given.
    $script:NewPackage = {
        param($Manifest, $Files, [switch]$Checksums, [hashtable]$Tamper)
        $Content = [ordered]@{}
        if ($Manifest) { $Content['addon.json'] = [System.Text.Encoding]::UTF8.GetBytes(($Manifest | ConvertTo-Json -Depth 6)) }
        foreach ($K in $Files.Keys) { $Content[$K] = [System.Text.Encoding]::UTF8.GetBytes($Files[$K]) }
        if ($Checksums) {
            $Sums = [ordered]@{}
            foreach ($K in $Content.Keys) { $Sums[$K] = & $script:Hex $Content[$K] }
            $Content['checksums.json'] = [System.Text.Encoding]::UTF8.GetBytes((@{ schema = 1; packagedOn = '11.2.1'; packagedAt = '2026-10-30T00:00:00Z'; files = $Sums } | ConvertTo-Json -Depth 4))
        }
        if ($Tamper) { foreach ($K in $Tamper.Keys) { $Content[$K] = [System.Text.Encoding]::UTF8.GetBytes($Tamper[$K]) } }
        $Stream = [System.IO.MemoryStream]::new()
        $Zip = [System.IO.Compression.ZipArchive]::new($Stream, [System.IO.Compression.ZipArchiveMode]::Create, $true)
        foreach ($K in $Content.Keys) {
            $W = $Zip.CreateEntry($K).Open(); $W.Write($Content[$K], 0, $Content[$K].Length); $W.Dispose()
        }
        $Zip.Dispose()
        , $Stream.ToArray()
    }
    $script:Request = { param($Body, $Endpoint = 'ExecAddon') @{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@contoso.com"}')) }; Body = $Body; Query = @{} } }
}

Describe 'Community Additions add-ons' {
    BeforeEach {
        $script:Saved = [System.Collections.Generic.List[object]]::new()
        $script:Removed = [System.Collections.Generic.List[object]]::new()
        $script:FlagSet = $null
    }

    Describe 'Compare-CIPPVersion' {
        It 'compares <A> with <B> as <Expected>' -ForEach @(
            @{ A = '11.2.1'; B = '11.2.1'; Expected = 0 }
            @{ A = '11.2.1'; B = '11.10.0'; Expected = -1 }
            @{ A = '12.0.0'; B = '11.99.99'; Expected = 1 }
            @{ A = '11.2.1+preview.reports.abc'; B = '11.2.1'; Expected = 0 }
            @{ A = '11.2'; B = '11.2.0'; Expected = 0 }
        ) {
            Compare-CIPPVersion $A $B | Should -Be $Expected
        }
    }

    Describe 'Get-CIPPRunningVersion' {
        It 'reads version_latest.txt' {
            $Expected = ((Get-Content (Join-Path $env:CIPPRootPath 'version_latest.txt') -Raw).Trim() -replace '^v')
            Get-CIPPRunningVersion | Should -Be $Expected
        }
        It "falls back to the image's APP_VERSION without its build suffix" {
            $Saved = $env:CIPPRootPath; $SavedApp = $env:APP_VERSION
            try {
                $env:CIPPRootPath = Join-Path $TestDrive 'empty'; $null = New-Item -ItemType Directory -Path $env:CIPPRootPath -Force
                $env:APP_VERSION = '11.3.0+preview.reports.abc1234'
                Get-CIPPRunningVersion | Should -Be '11.3.0'
            } finally { $env:CIPPRootPath = $Saved; $env:APP_VERSION = $SavedApp }
        }
    }

    Describe 'Test-CIPPAddonManifest' {
        It 'accepts a good manifest' {
            @(Test-CIPPAddonManifest -Manifest ([pscustomobject](& $script:GoodManifest | ConvertTo-Json -Depth 6 | ConvertFrom-Json))) | Should -BeNullOrEmpty
        }
        It 'reports <Why>' -ForEach @(
            @{ Why = 'a bad id'; Change = { param($M) $M.id = 'Demo Addon' }; Match = 'id must be' }
            @{ Why = 'a folder mismatch'; Change = { param($M) }; Folder = 'other'; Match = "doesn't match its folder" }
            @{ Why = 'a bad version'; Change = { param($M) $M.version = '1.0' }; Match = 'version must' }
            @{ Why = 'no tested versions'; Change = { param($M) $M.cipp.testedWith = @() }; Match = 'testedWith must list' }
            @{ Why = 'a menu path outside /addons/<id>'; Change = { param($M) $M.menu[0].path = '/tenant/administration/demo' }; Match = 'path under /addons/demo-addon' }
            @{ Why = 'a menu entry without permissions'; Change = { param($M) $M.menu[0].permissions = @() }; Match = 'no permissions' }
        ) {
            $M = & $script:GoodManifest
            & $Change $M
            $Problems = @(Test-CIPPAddonManifest -Manifest ($M | ConvertTo-Json -Depth 6 | ConvertFrom-Json) -Id ($Folder ?? 'demo-addon'))
            ($Problems -join ' ') | Should -Match $Match
        }
    }

    Describe 'Test-CIPPAddonCompatibility' {
        BeforeAll {
            function Get-CIPPDemoPresent { }
            function Invoke-ExecDemoAddon { }
            $script:Compat = {
                param([string]$Version, $Functions = @('Get-CIPPDemoPresent'), $Tested = @('11.2.1'), $Min = '11.0.0')
                $M = [pscustomobject]@{
                    schema = 1; id = 'demo-addon'; name = 'Demo'; version = '1.0.0'
                    cipp = [pscustomobject]@{ minVersion = $Min; testedWith = $Tested }
                    endpoints = @('ExecDemoAddon'); dependsOn = [pscustomobject]@{ functions = $Functions }
                }
                Test-CIPPAddonCompatibility -Manifest $M -CippVersion $Version
            }
        }
        It 'is Compatible when tested on the same major.minor and nothing is missing' {
            (& $script:Compat '11.2.4').Status | Should -Be 'Compatible'
        }
        It 'is Untested on a newer minor version, saying when it was last tested' {
            $R = & $script:Compat '11.3.0'
            $R.Status | Should -Be 'Untested'
            $R.Message | Should -Match '11\.2\.1'
        }
        It 'is NeedsNewerCipp below minVersion' {
            (& $script:Compat '10.9.0' -Min '11.0.0').Status | Should -Be 'NeedsNewerCipp'
        }
        It 'is a Problem, naming it, when a CIPP function it uses is gone' {
            $R = & $script:Compat '11.2.1' -Functions @('Get-CIPPDemoPresent', 'Get-CIPPGoneUpstream')
            $R.Status | Should -Be 'Problem'
            $R.MissingFunctions | Should -Be @('Get-CIPPGoneUpstream')
            $R.Message | Should -Match 'Get-CIPPGoneUpstream'
        }
        It 'skips the runtime lookups with -SkipRuntimeCheck (an uploaded package)' {
            $M = [pscustomobject]@{ schema = 1; id = 'demo-addon'; name = 'Demo'; version = '1.0.0'; cipp = [pscustomobject]@{ minVersion = '11.0.0'; testedWith = @('11.2.1') }; dependsOn = [pscustomobject]@{ functions = @('Get-CIPPGoneUpstream') } }
            (Test-CIPPAddonCompatibility -Manifest $M -CippVersion '11.2.1' -SkipRuntimeCheck).Status | Should -Be 'Compatible'
        }
    }

    Describe 'Test-CIPPAddonPackage' {
        It 'accepts a good package with checksums' {
            $R = Test-CIPPAddonPackage -Bytes (& $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles) -Checksums) -Layout $script:Layout
            $R.Errors | Should -BeNullOrEmpty
            $R.Valid | Should -BeTrue
            $R.Manifest.id | Should -Be 'demo-addon'
            $R.Files.Count | Should -Be 5
            $R.PackagedOn | Should -Be '11.2.1'
        }
        It 'warns, but accepts, a package without checksums' {
            $R = Test-CIPPAddonPackage -Bytes (& $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles)) -Layout $script:Layout
            $R.Valid | Should -BeTrue
            $R.Warnings -join ' ' | Should -Match 'checksums'
        }
        It 'refuses something that is not a zip' {
            $R = Test-CIPPAddonPackage -Bytes ([System.Text.Encoding]::UTF8.GetBytes('not a zip')) -Layout $script:Layout
            $R.Valid | Should -BeFalse
            $R.Errors -join ' ' | Should -Match '\.zip'
        }
        It 'refuses <Why>' -ForEach @(
            @{ Why = 'a path that climbs out'; Extra = @{ 'backend/functions/../../evil.ps1' = 'x' }; Match = 'plain relative path' }
            @{ Why = 'a file outside the add-on folders'; Extra = @{ 'backend/Modules/CIPPCore/Public/Get-Tenants.ps1' = 'x' }; Match = "isn't in one of the add-on folders" }
            @{ Why = 'a file type its folder does not allow'; Extra = @{ 'frontend/components/run.ps1' = 'x' }; Match = 'can only be' }
            @{ Why = 'code outside the function'; Extra = @{ 'backend/functions/Get-CIPPDemoOther.ps1' = "Remove-Item /x`nfunction Get-CIPPDemoOther { }" }; Match = 'code outside its function' }
            @{ Why = 'a file defining a different function'; Extra = @{ 'backend/functions/Get-CIPPDemoOther.ps1' = 'function Get-Tenants { }' }; Match = 'exactly one function, Get-CIPPDemoOther' }
            @{ Why = 'an endpoint not listed in addon.json'; Extra = @{ 'backend/endpoints/Invoke-ExecHidden.ps1' = 'function Invoke-ExecHidden { }' }; Match = "isn't listed under endpoints" }
            @{ Why = 'a script that does not parse'; Extra = @{ 'backend/functions/Get-CIPPDemoOther.ps1' = 'function Get-CIPPDemoOther { (' }; Match = "doesn't parse" }
        ) {
            $Files = & $script:GoodFiles
            foreach ($K in $Extra.Keys) { $Files[$K] = $Extra[$K] }
            $R = Test-CIPPAddonPackage -Bytes (& $script:NewPackage (& $script:GoodManifest) $Files) -Layout $script:Layout
            $R.Valid | Should -BeFalse
            $R.Errors -join ' ' | Should -Match ([regex]::Escape($Match) -replace '\\ ', ' ')
        }
        It 'refuses a package with no addon.json' {
            $R = Test-CIPPAddonPackage -Bytes (& $script:NewPackage $null (& $script:GoodFiles)) -Layout $script:Layout
            $R.Errors -join ' ' | Should -Match 'no addon.json'
        }
        It 'refuses a listed endpoint with no file, and a menu entry with no page' {
            $Files = & $script:GoodFiles
            $Files.Remove('backend/endpoints/Invoke-ExecDemoAddon.ps1')
            $Files.Remove('frontend/pages/index.jsx')
            $Errors = (Test-CIPPAddonPackage -Bytes (& $script:NewPackage (& $script:GoodManifest) $Files) -Layout $script:Layout).Errors -join ' '
            $Errors | Should -Match 'Invoke-ExecDemoAddon.ps1'
            $Errors | Should -Match 'menu entry /addons/demo-addon has no page'
        }
        It 'notices a file changed after packaging' {
            $Bytes = & $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles) -Checksums -Tamper @{ 'backend/functions/Get-CIPPDemoThing.ps1' = "function Get-CIPPDemoThing { 'changed' }" }
            $R = Test-CIPPAddonPackage -Bytes $Bytes -Layout $script:Layout
            $R.Valid | Should -BeFalse
            $R.Errors -join ' ' | Should -Match "doesn't match its checksum"
        }
        It 'enforces the file-count limit' {
            $Small = $script:Layout | ConvertTo-Json -Depth 6 | ConvertFrom-Json
            $Small.limits.files = 3
            $R = Test-CIPPAddonPackage -Bytes (& $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles)) -Layout $Small
            $R.Errors -join ' ' | Should -Match 'the limit is 3'
        }
    }

    Describe 'Add-on feature flags' {
        It 'gives each installed add-on a hidden, user-toggleable flag covering its endpoints and pages' {
            $Flags = @(Get-CIPPAddonFeatureFlags -Refresh)
            $Claude = $Flags | Where-Object { $_.Id -eq 'Addon.claude-m365' }
            $Claude | Should -Not -BeNullOrEmpty
            $Claude.Hidden | Should -BeTrue
            $Claude.AllowUserToggle | Should -BeTrue
            $Claude.Endpoints | Should -Contain 'ExecClaudeConnector'
            $Claude.Pages | Should -Contain '/addons/claude-m365'
        }
        It 'are part of Get-CIPPFeatureFlag, seeded on, so New-CippCoreRequest and the menu honour them' {
            $Flag = Get-CIPPFeatureFlag -Id 'Addon.claude-m365'
            $Flag.Enabled | Should -BeTrue
            $Flag.Endpoints | Should -Contain 'ListClaudeConnector'
            ($script:Saved | Where-Object { $_.RowKey -eq 'Addon.claude-m365' }).Enabled | Should -BeTrue
        }
    }

    Describe 'Invoke-ExecAddon' {
        It 'turns an installed add-on off through its feature flag' {
            $R = Invoke-ExecAddon -Request (& $script:Request @{ Action = 'Disable'; Id = 'claude-m365' })
            $R.StatusCode | Should -Be 200
            $script:FlagSet.Id | Should -Be 'Addon.claude-m365'
            $script:FlagSet.Enabled | Should -BeFalse
        }
        It 'refuses an add-on that is not installed' {
            (Invoke-ExecAddon -Request (& $script:Request @{ Action = 'Enable'; Id = 'no-such-addon' })).StatusCode | Should -Be 404
            $script:FlagSet | Should -BeNullOrEmpty
        }
        It 'checks and keeps a good upload, the package apart from its details' {
            $Data = [Convert]::ToBase64String((& $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles) -Checksums))
            $R = Invoke-ExecAddon -Request (& $script:Request @{ Action = 'Upload'; FileName = 'C:\fakepath\demo-addon-1.0.0.zip'; Data = "data:application/zip;base64,$Data" })
            $R.StatusCode | Should -Be 200
            $Meta = $script:Saved | Where-Object { $_.PartitionKey -eq 'Upload' }
            $Meta.RowKey | Should -Be 'demo-addon_1.0.0'
            $Meta.FileName | Should -Be 'demo-addon-1.0.0.zip'
            $Meta.UploadedBy | Should -Be 'admin@contoso.com'
            $Meta.PSObject.Properties.Name | Should -Not -Contain 'Package'
            ($script:Saved | Where-Object { $_.PartitionKey -eq 'UploadData' }).Package | Should -Be $Data
        }
        It 'refuses a bad upload with the reasons and keeps nothing' {
            $Files = & $script:GoodFiles
            $Files['backend/functions/../x.ps1'] = 'x'
            $R = Invoke-ExecAddon -Request (& $script:Request @{ Action = 'Upload'; FileName = 'bad.zip'; Data = [Convert]::ToBase64String((& $script:NewPackage (& $script:GoodManifest) $Files)) })
            $R.StatusCode | Should -Be 400
            $R.Body.Errors -join ' ' | Should -Match 'plain relative path'
            $script:Saved.Count | Should -Be 0
        }
        It 'refuses an upload whose function names clash with CIPP' {
            function Get-CIPPDemoThing { }
            $R = Invoke-ExecAddon -Request (& $script:Request @{ Action = 'Upload'; FileName = 'demo.zip'; Data = [Convert]::ToBase64String((& $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles))) })
            $R.StatusCode | Should -Be 400
            $R.Body.Errors -join ' ' | Should -Match 'Get-CIPPDemoThing is already a CIPP function'
        }
        It 'refuses a file that is not a .zip' {
            (Invoke-ExecAddon -Request (& $script:Request @{ Action = 'Upload'; FileName = 'demo.exe'; Data = 'AAAA' })).StatusCode | Should -Be 400
        }
        It 'deletes an upload and its package, and refuses a made-up RowKey' {
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'Upload'; RowKey = 'demo-addon_1.0.0'; Name = 'Demo'; Version = '1.0.0' })
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'UploadData'; RowKey = 'demo-addon_1.0.0'; Package = 'AA==' })
            (Invoke-ExecAddon -Request (& $script:Request @{ Action = 'DeleteUpload'; RowKey = "x' or RowKey ne '" })).StatusCode | Should -Be 400
            (Invoke-ExecAddon -Request (& $script:Request @{ Action = 'DeleteUpload'; RowKey = 'demo-addon_1.0.0' })).StatusCode | Should -Be 200
            $script:Removed.Count | Should -Be 2
        }
    }

    Describe 'Invoke-ExecAddonDownload' {
        It 'returns an uploaded package as a zip' {
            $Bytes = & $script:NewPackage (& $script:GoodManifest) (& $script:GoodFiles)
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'Upload'; RowKey = 'demo-addon_1.0.0'; AddonId = 'demo-addon'; Version = '1.0.0' })
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'UploadData'; RowKey = 'demo-addon_1.0.0'; Package = [Convert]::ToBase64String($Bytes) })
            $R = Invoke-ExecAddonDownload -Request (& $script:Request @{ RowKey = 'demo-addon_1.0.0' } 'ExecAddonDownload')
            $R.StatusCode | Should -Be 200
            $R.ContentType | Should -Be 'application/zip'
            $R.Headers.'Content-Disposition' | Should -Match 'demo-addon-1.0.0.zip'
            [Convert]::ToBase64String($R.Body) | Should -Be ([Convert]::ToBase64String($Bytes))
        }
        It "says so when this build has no package for an installed add-on" {
            $R = Invoke-ExecAddonDownload -Request (& $script:Request @{ Id = 'claude-m365' } 'ExecAddonDownload')
            $R.StatusCode | Should -Be 404
            $R.Body | Should -Match 'Export-CippAddon'
        }
    }

    Describe 'Invoke-ListAddons' {
        It 'lists the installed add-ons with their state and the uploads' {
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'Upload'; RowKey = 'claude-m365_9.0.0'; AddonId = 'claude-m365'; Name = 'Claude'; Version = '9.0.0'; MinVersion = '11.0.0'; TestedWith = '11.2.1'; Warnings = '["no tests"]'; UploadedAt = '2026-10-30T00:00:00Z' })
            $R = Invoke-ListAddons -Request (& $script:Request @{} 'ListAddons')
            $R.StatusCode | Should -Be 200
            $R.Body.CippVersion | Should -Not -BeNullOrEmpty
            $R.Body.LatestCippVersion | Should -BeNullOrEmpty   # offline in tests
            $Claude = $R.Body.Addons | Where-Object { $_.Id -eq 'claude-m365' }
            $Claude.Enabled | Should -BeTrue
            $Claude.Status | Should -BeIn 'Compatible', 'Untested', 'Problem'
            $Upload = $R.Body.Uploads | Select-Object -First 1
            $Upload.Installed | Should -Be 'Upgrade'
            $Upload.Warnings | Should -Be @('no tests')
        }
    }

    Describe 'Installed add-on <Id>' -ForEach @(
        Get-ChildItem -Path (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'Config/Addons') -Directory |
            Where-Object { Test-Path (Join-Path $_.FullName 'addon.json') } | ForEach-Object { @{ Id = $_.Name } }
    ) {
        BeforeAll {
            . (Join-Path $script:Root 'build/tools/addons/AddonTools.ps1')
            $script:M = Get-Content (Join-Path $script:Root "backend/Config/Addons/$Id/addon.json") -Raw | ConvertFrom-Json
            $script:CoreIndex = Get-AddonCoreFunctionIndex
        }
        It 'has a valid manifest' {
            @(Test-CIPPAddonManifest -Manifest $script:M -Id $Id) | Should -BeNullOrEmpty
        }
        It 'packages cleanly with the same checks as an upload' {
            $Result = & (Join-Path $script:Root 'build/tools/addons/Export-CippAddon.ps1') -Id $Id -OutputPath (Join-Path $TestDrive 'pk') -WarningAction SilentlyContinue
            $Result.Path | Should -Exist
            (Test-CIPPAddonPackage -Path $Result.Path -Layout (Get-AddonToolLayout)).Valid | Should -BeTrue
        }
        It 'lists in dependsOn exactly what its code uses from CIPP (run Update-CippAddonDependencies.ps1 if not)' {
            $Deps = Get-AddonDependencies -Id $Id -CoreIndex $script:CoreIndex
            Compare-Object @($script:M.dependsOn.functions) @($Deps.functions) | ForEach-Object { "$($_.InputObject) $(if ($_.SideIndicator -eq '=>') { 'is used but not listed' } else { 'is listed but not used' })" } | Should -BeNullOrEmpty
            Compare-Object @($script:M.dependsOn.frontend) @($Deps.frontend) | ForEach-Object { "$($_.InputObject) $(if ($_.SideIndicator -eq '=>') { 'is imported but not listed' } else { 'is listed but not imported' })" } | Should -BeNullOrEmpty
        }
        It 'finds every CIPP function and frontend file it depends on' {
            $Missing = @($script:M.dependsOn.functions | Where-Object { -not $script:CoreIndex.ContainsKey($_) })
            $Missing += @($script:M.dependsOn.frontend | Where-Object { -not (Resolve-AddonFrontendFile -Spec $_ -Exists { param($P) Test-Path (Join-Path $script:Root $P) }) })
            $Missing | Should -BeNullOrEmpty
        }
        It 'has no function or endpoint named like one of CIPP''s own' {
            $Own = @()
            foreach ($Area in (Get-AddonToolLayout).areas | Where-Object { $_.package -in 'backend/functions', 'backend/endpoints' }) {
                $Folder = Get-AddonRepoPath -Template $Area.repo -Id $Id
                if (Test-Path $Folder) { $Own += @(Get-ChildItem $Folder -Filter '*.ps1' -Recurse | ForEach-Object { $_.BaseName }) }
            }
            @($Own | Where-Object { $script:CoreIndex.ContainsKey($_) }) | Should -BeNullOrEmpty
        }
        It 'gives every endpoint a role' {
            foreach ($E in @($script:M.endpoints)) {
                $File = Get-ChildItem (Join-Path $script:Root 'backend/Modules/CIPPHTTP') -Recurse -Filter "Invoke-$E.ps1" | Select-Object -First 1
                $File | Should -Not -BeNullOrEmpty -Because "Invoke-$E.ps1 should exist"
                (Get-Content $File.FullName -Raw) | Should -Match '\.ROLE\s+\S+'
            }
        }
        It 'has been tested on this CIPP version (add it to cipp.testedWith once checked)' {
            $Here = (Get-AddonRepoVersion) -split '\.'
            $Tested = @($script:M.cipp.testedWith | Where-Object { (($_ -split '\.')[0..1] -join '.') -eq ($Here[0..1] -join '.') })
            $Tested | Should -Not -BeNullOrEmpty -Because "CIPP $(Get-AddonRepoVersion) is not in testedWith ($(@($script:M.cipp.testedWith) -join ', '))"
        }
    }
}
