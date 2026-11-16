# Pester tests for the password hand-over add-on (password-handover): settings and their checks, the
# message, the reset-and-link flow (cloud and directory-synced users, no server, a failed push) and the
# endpoints. Graph, the tables and Password Pusher are faked in memory; the data is synthetic.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))   # backend
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
        [string]$ContentType
        [hashtable]$Headers
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    $env:CIPPRootPath = $RepoRoot
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) $script:Logs.Add("$message") }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function Get-CIPPTable { param($TableName) @{ Context = $TableName } }
    function Get-CIPPAzDataTableEntity {
        param($Context, $Filter)
        if ($Context -eq 'Extensionsconfig') { return $script:ExtConfig }
        @($script:Saved | Where-Object { $Filter -match "PartitionKey eq '$($_.PartitionKey)'" -and $Filter -match "RowKey eq '$($_.RowKey)'" })
    }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Saved.Add([pscustomobject]$Entity) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $null = $script:Saved.Remove($Entity) }
    function Get-ExtensionAPIKey { param($Extension) "key-for-$Extension" }
    function Get-CIPPPwPushVersion { param($BaseUrl, $Headers) [pscustomobject]@{ ApiVersion = 'v2' } }
    function New-passwordString { 'Synthetic-Pass-123' }
    function New-GraphGetRequest {
        param($uri, $tenantid, $noPagination)
        $script:Calls.Add("GET $uri")
        $script:User
    }
    function New-GraphPostRequest {
        param($uri, $tenantid, $type, $body)
        $script:Calls.Add("$type $uri $body")
    }
    function New-CIPPPwPush {
        param($Connection, $Payload, $ExpireAfterDays, $ExpireAfterViews, $DeletableByViewer, $RetrievalStep, $Passphrase, $WorkspaceId)
        if ($script:PushFails) { throw 'PWPush API returned HTTP 500' }
        $script:Push = $PSBoundParameters
        [pscustomobject]@{ Link = "$($Connection.BaseUrl)/p/tok123/r"; UrlToken = 'tok123' }
    }

    foreach ($Name in 'Get-CIPPPasswordHandoverSettings', 'Test-CIPPPasswordHandoverSettings', 'Get-CIPPPasswordHandoverConnection',
        'Format-CIPPPasswordHandoverMessage', 'New-CIPPPasswordHandover',
        'Invoke-ExecPasswordHandover', 'Invoke-ListPasswordHandover', 'Invoke-ExecPasswordHandoverSettings') {
        . (& $Find "$Name.ps1")
    }
    $script:Request = { param($Body, $Endpoint = 'ExecPasswordHandover') @{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{}; Body = $Body; Query = @{} } }
    $script:Server = { param([hashtable]$PwPush = @{ Enabled = $false; BaseUrl = 'https://pw.example.com/'; UseBearerAuth = $true }) [pscustomobject]@{ config = (@{ PWPush = $PwPush } | ConvertTo-Json -Depth 5) } }
}

Describe 'Password hand-over add-on' {
    BeforeEach {
        $script:Saved = [System.Collections.Generic.List[object]]::new()
        $script:Calls = [System.Collections.Generic.List[string]]::new()
        $script:Logs = [System.Collections.Generic.List[string]]::new()
        $script:ExtConfig = & $script:Server
        $script:User = [pscustomobject]@{ id = '11111111-1111-1111-1111-111111111111'; displayName = 'Jane Smith'; userPrincipalName = 'jane@contoso.com'; onPremisesSyncEnabled = $null }
        $script:Push = $null
        $script:PushFails = $false
    }

    Describe 'Settings' {
        It 'starts at 14 days, 7 views and the email address as the passphrase' {
            $S = Get-CIPPPasswordHandoverSettings
            $S.expireAfterDays | Should -Be 14
            $S.expireAfterViews | Should -Be 7
            $S.passphrase | Should -Be 'email'
            $S.retrievalStep | Should -BeTrue
            $S.Saved | Should -BeFalse
            $S.message | Should -Match '\{link\}'
        }
        It 'uses saved settings over the defaults' {
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'password-handover'; RowKey = 'settings'; Settings = '{"expireAfterDays":3,"expireAfterViews":2,"passphrase":"none"}' })
            $S = Get-CIPPPasswordHandoverSettings
            $S.expireAfterDays | Should -Be 3
            $S.expireAfterViews | Should -Be 2
            $S.passphrase | Should -Be 'none'
            $S.subject | Should -Not -BeNullOrEmpty
            $S.Saved | Should -BeTrue
        }
        It 'refuses <Why>' -ForEach @(
            @{ Why = 'too many days'; Change = @{ expireAfterDays = 91 }; Message = '1 to 90 days' }
            @{ Why = 'no views'; Change = @{ expireAfterViews = 0 }; Message = '1 to 100 times' }
            @{ Why = 'an odd passphrase'; Change = @{ passphrase = 'secret' }; Message = 'email address or none' }
            @{ Why = 'a plain http sign-in address'; Change = @{ signInUrl = 'http://office.com' }; Message = 'https' }
            @{ Why = 'a message with no link'; Change = @{ message = 'Hello' }; Message = '\{link\}' }
            @{ Why = 'a plain http server'; Change = @{ serverUrl = 'http://pw.example.com' }; Message = 'Password Pusher address' }
        ) {
            $Good = @{ expireAfterDays = 14; expireAfterViews = 7; passphrase = 'email'; retrievalStep = $true; mustChange = $true; signInUrl = 'https://www.office.com'; subject = 'Hi'; message = 'Here: {link}' }
            foreach ($K in $Change.Keys) { $Good[$K] = $Change[$K] }
            { Test-CIPPPasswordHandoverSettings -Settings ([pscustomobject]$Good) } | Should -Throw "*$($Message -replace '\\', '')*"
        }
    }

    Describe 'Format-CIPPPasswordHandoverMessage' {
        It 'fills in every placeholder and leaves unknown ones alone' {
            $S = Get-CIPPPasswordHandoverSettings
            $Text = Format-CIPPPasswordHandoverMessage -Template "$($S.message) {other}" -Settings $S -DisplayName 'Jane Smith' -UserPrincipalName 'jane@contoso.com' -Link 'https://pw.example.com/p/x' -ExpiresOn ([datetime]'2026-11-30') -MustChange $true
            $Text | Should -Match 'Jane Smith \(jane@contoso.com\)'
            $Text | Should -Match 'https://pw.example.com/p/x'
            $Text | Should -Match 'opened 7 times'
            $Text | Should -Match 'Monday 30 November 2026'
            $Text | Should -Match 'passphrase, enter the email address'
            $Text | Should -Match 'choose your own password'
            $Text | Should -Match '\{other\}'
            $Text | Should -Not -Match '\{(link|views|displayName|passphraseLine|mustChangeLine)\}'
        }
        It 'leaves out the passphrase and change sentences when they do not apply' {
            $S = Get-CIPPPasswordHandoverSettings
            $S.passphrase = 'none'
            $Text = Format-CIPPPasswordHandoverMessage -Template $S.message -Settings $S -Link 'x' -ExpiresOn (Get-Date) -MustChange $false
            $Text | Should -Not -Match 'passphrase'
            $Text | Should -Not -Match 'choose your own password'
        }
    }

    Describe 'New-CIPPPasswordHandover' {
        It 'resets nothing when no Password Pusher server is set up' {
            $script:ExtConfig = $null
            { New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com' } | Should -Throw '*Set up Password Pusher first*'
            @($script:Calls | Where-Object { $_ -match '^(PATCH|POST)' }).Count | Should -Be 0
        }
        It 'resets a cloud user and makes a 14-day, 7-view link with their email as passphrase' {
            $R = New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com'
            $Patch = @($script:Calls | Where-Object { $_ -like 'PATCH*' })
            $Patch.Count | Should -Be 1
            $Patch[0] | Should -Match '"forceChangePasswordNextSignIn":true'
            $script:Push.ExpireAfterDays | Should -Be 14
            $script:Push.ExpireAfterViews | Should -Be 7
            $script:Push.Passphrase | Should -Be 'jane@contoso.com'
            $script:Push.RetrievalStep | Should -BeTrue
            $script:Push.Payload | Should -Be 'Synthetic-Pass-123'
            $script:Push.Connection.BaseUrl | Should -Be 'https://pw.example.com'
            $script:Push.Connection.Headers.Authorization | Should -Be 'Bearer key-for-PWPush'
            $R.Count | Should -Be 2
            $R[0].copyField | Should -Be 'https://pw.example.com/p/tok123/r'
            $R[0].state | Should -Be 'success'
            $R[1].copyField | Should -Match 'https://pw.example.com/p/tok123/r'
            $R[1].resultText | Should -Match 'Subject: New password for Jane Smith'
        }
        It 'never logs or returns the password when the link is made' {
            $R = New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com'
            ($R | ConvertTo-Json) | Should -Not -Match 'Synthetic-Pass-123'
            ($script:Logs -join ' ') | Should -Not -Match 'Synthetic-Pass-123|tok123'
        }
        It 'takes the days, views and change-at-sign-in chosen in the dialog' {
            $null = New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com' -ExpireAfterDays 3 -ExpireAfterViews 1 -MustChange $false
            $script:Push.ExpireAfterDays | Should -Be 3
            $script:Push.ExpireAfterViews | Should -Be 1
            @($script:Calls | Where-Object { $_ -like 'PATCH*' })[0] | Should -Match '"forceChangePasswordNextSignIn":false'
        }
        It 'resets a directory-synced user through password writeback' {
            $script:User.onPremisesSyncEnabled = $true
            $R = New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com' -MustChange $false
            @($script:Calls | Where-Object { $_ -like 'POST*resetPassword*' }).Count | Should -Be 1
            @($script:Calls | Where-Object { $_ -like 'PATCH*' }).Count | Should -Be 0
            $R[0].resultText | Should -Match 'password writeback'
            $R[1].copyField | Should -Match 'choose your own password'
        }
        It 'resets nothing, and never shows the password, when the link fails' {
            $script:PushFails = $true
            { New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com' } | Should -Throw '*was not reset*'
            @($script:Calls | Where-Object { $_ -match '^(PATCH|POST)' }).Count | Should -Be 0
        }
        It 'uses the add-on''s own server without the integration''s API key' {
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'password-handover'; RowKey = 'settings'; Settings = '{"serverUrl":"https://own.example.com/"}' })
            $null = New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com'
            $script:Push.Connection.BaseUrl | Should -Be 'https://own.example.com'
            $script:Push.Connection.Headers.ContainsKey('Authorization') | Should -BeFalse
        }
        It 'works with only the add-on''s server and no integration at all' {
            $script:ExtConfig = $null
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'password-handover'; RowKey = 'settings'; Settings = '{"serverUrl":"https://own.example.com"}' })
            (New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com')[0].copyField | Should -Be 'https://own.example.com/p/tok123/r'
        }
        It 'refuses a server address that is not https' {
            $script:ExtConfig = & $script:Server @{ BaseUrl = 'http://pw.example.com' }
            { New-CIPPPasswordHandover -TenantFilter 'contoso.com' -UserID 'jane@contoso.com' } | Should -Throw '*https*'
        }
    }

    Describe 'Endpoints' {
        It 'ExecPasswordHandover refuses <Why>' -ForEach @(
            @{ Why = 'all tenants'; Body = @{ tenantFilter = 'AllTenants'; ID = 'jane@contoso.com' } }
            @{ Why = 'no user'; Body = @{ tenantFilter = 'contoso.com' } }
            @{ Why = 'days that are not a number'; Body = @{ tenantFilter = 'contoso.com'; ID = 'jane@contoso.com'; ExpireAfterDays = 'soon' } }
        ) {
            (Invoke-ExecPasswordHandover -Request (& $script:Request $Body)).StatusCode | Should -Be 400
            $script:Calls.Count | Should -Be 0
        }
        It 'ExecPasswordHandover returns the link and the message' {
            $R = Invoke-ExecPasswordHandover -Request (& $script:Request @{ tenantFilter = 'contoso.com'; ID = 'jane@contoso.com'; displayName = 'Jane Smith'; MustChange = $true; ExpireAfterDays = $null })
            $R.StatusCode | Should -Be 200
            @($R.Body.Results).Count | Should -Be 2
        }
        It 'ExecPasswordHandover says why when nothing could be done' {
            $script:ExtConfig = $null
            $R = Invoke-ExecPasswordHandover -Request (& $script:Request @{ tenantFilter = 'contoso.com'; ID = 'jane@contoso.com' })
            $R.StatusCode | Should -Be 500
            $R.Body.Results | Should -Match "wasn't handed over"
        }
        It 'ListPasswordHandover gives the settings and the server without the API key' {
            $R = Invoke-ListPasswordHandover -Request (& $script:Request @{} 'ListPasswordHandover')
            $R.Body.Settings.expireAfterDays | Should -Be 14
            $R.Body.Server.Configured | Should -BeTrue
            $R.Body.Server.Authenticated | Should -BeTrue
            ($R.Body | ConvertTo-Json -Depth 5) | Should -Not -Match 'key-for'
        }
        It 'ExecPasswordHandoverSettings saves good settings and goes back to the defaults' {
            $Settings = @{ expireAfterDays = 10; expireAfterViews = 5; passphrase = 'none'; retrievalStep = $false; mustChange = $true; signInUrl = 'https://www.office.com'; subject = 'Your password'; message = 'Link: {link}' }
            (Invoke-ExecPasswordHandoverSettings -Request (& $script:Request @{ Settings = $Settings } 'ExecPasswordHandoverSettings')).StatusCode | Should -Be 200
            (Get-CIPPPasswordHandoverSettings).expireAfterDays | Should -Be 10
            (Invoke-ExecPasswordHandoverSettings -Request (& $script:Request @{ Reset = $true } 'ExecPasswordHandoverSettings')).StatusCode | Should -Be 200
            (Get-CIPPPasswordHandoverSettings).expireAfterDays | Should -Be 14
        }
        It 'ExecPasswordHandoverSettings makes a throwaway test link on the address given' {
            $R = Invoke-ExecPasswordHandoverSettings -Request (& $script:Request @{ Test = $true; Settings = @{ serverUrl = 'https://own.example.com' } } 'ExecPasswordHandoverSettings')
            $R.StatusCode | Should -Be 200
            $R.Body.Results | Should -Match 'It works: https://own.example.com'
            $script:Push.ExpireAfterViews | Should -Be 1
            $script:Push.Payload | Should -Match 'test link'
            $script:PushFails = $true
            (Invoke-ExecPasswordHandoverSettings -Request (& $script:Request @{ Test = $true; Settings = @{} } 'ExecPasswordHandoverSettings')).Body.Results | Should -Match "couldn't be made"
            $script:Saved.Count | Should -Be 0
        }
        It 'ListPasswordHandover says when the add-on uses its own server' {
            $script:Saved.Add([pscustomobject]@{ PartitionKey = 'password-handover'; RowKey = 'settings'; Settings = '{"serverUrl":"https://own.example.com"}' })
            $R = Invoke-ListPasswordHandover -Request (& $script:Request @{} 'ListPasswordHandover')
            $R.Body.Server.Source | Should -Be 'addon'
            $R.Body.Server.Authenticated | Should -BeFalse
        }
        It 'ExecPasswordHandoverSettings refuses bad settings and keeps nothing' {
            $R = Invoke-ExecPasswordHandoverSettings -Request (& $script:Request @{ Settings = @{ expireAfterDays = 200 } } 'ExecPasswordHandoverSettings')
            $R.StatusCode | Should -Be 400
            $script:Saved.Count | Should -Be 0
        }
    }
}
