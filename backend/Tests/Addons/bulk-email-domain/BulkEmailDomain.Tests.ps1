# Pester tests for the bulk email domain add-on (bulk-email-domain): adding an address on a domain to many
# users as an alias or as their new primary address, what is skipped and why, and the endpoint's checks.
# Exchange and Graph are faked in memory.

BeforeAll {
    $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))   # backend
    $Find = { param($Name) Get-ChildItem -Path (Join-Path $RepoRoot 'Modules') -Recurse -Filter $Name -File | Select-Object -First 1 -ExpandProperty FullName }

    class HttpResponseContext {
        [int]$StatusCode
        [object]$Body
    }
    $Accelerators = [PSObject].Assembly.GetType('System.Management.Automation.TypeAccelerators')
    if (-not ('HttpStatusCode' -as [type])) { $Accelerators::Add('HttpStatusCode', [System.Net.HttpStatusCode]) }

    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) $script:Logs.Add($message) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function Get-NormalizedError { param($Message) "$Message" }

    $script:Ids = @{ james = '11111111-1111-1111-1111-111111111111'; carly = '22222222-2222-2222-2222-222222222222'; dawn = '33333333-3333-3333-3333-333333333333'; synced = '44444444-4444-4444-4444-444444444444'; guest = '55555555-5555-5555-5555-555555555555'; other = '66666666-6666-6666-6666-666666666666' }
    $script:NewTenant = {
        $script:Logs = [System.Collections.Generic.List[string]]::new()
        $script:Sent = [System.Collections.Generic.List[object]]::new()
        $script:FailFor = @()
        $Mbx = {
            param($Key, $Name, $Upn, $Addresses, $Synced = $false)
            [pscustomobject]@{ DisplayName = $Name; UserPrincipalName = $Upn; PrimarySmtpAddress = (($Addresses | Where-Object { $_ -cmatch '^SMTP:' }) -replace '^SMTP:'); EmailAddresses = $Addresses; ExternalDirectoryObjectId = $script:Ids[$Key]; IsDirSynced = $Synced; Guid = [guid]::NewGuid().ToString() }
        }
        $script:Mailboxes = @(
            (& $Mbx 'james' 'James Sherratt' 'james@jamessherratt.co.uk' @('SMTP:james@jamessherratt.co.uk', 'smtp:james@sherrattsestates.com', 'X500:/o=ExchangeLabs/cn=james'))
            (& $Mbx 'carly' 'Carly Sherratt' 'carly.sherratt@jamessherratt.co.uk' @('SMTP:carly@jamessherratt.co.uk', 'smtp:carly@sherrattbps.onmicrosoft.com'))
            (& $Mbx 'dawn' 'Dawn Lane' 'dawn@jamessherratt.co.uk' @('SMTP:dawn@jamessherratt.co.uk'))
            (& $Mbx 'synced' 'Old Server' 'old@jamessherratt.co.uk' @('SMTP:old@jamessherratt.co.uk') $true)
        )
        $script:OtherRecipients = @([pscustomobject]@{ DisplayName = 'Dawn (old contact)'; EmailAddresses = @('SMTP:dawnlane@sherrattsestates.com'); ExternalDirectoryObjectId = $script:Ids.other })
    }

    function New-GraphGetRequest {
        param($uri, $tenantid, $noPagination)
        @([pscustomobject]@{ id = 'jamessherratt.co.uk'; isVerified = $true }, [pscustomobject]@{ id = 'sherrattsestates.com'; isVerified = $true }, [pscustomobject]@{ id = 'notyet.com'; isVerified = $false })
    }
    function New-ExoRequest {
        param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox)
        switch ($cmdlet) {
            'Get-Mailbox' { return $script:Mailboxes }
            'Get-Recipient' { return @($script:Mailboxes) + @($script:OtherRecipients) }
            default { throw "Unexpected $cmdlet" }
        }
    }
    function New-ExoBulkRequest {
        param($tenantid, $cmdletArray, $useSystemMailbox)
        foreach ($R in $cmdletArray) {
            $script:Sent.Add($R)
            $M = $script:Mailboxes | Where-Object Guid -eq $R.CmdletInput.Parameters.Identity
            if ($script:FailFor -contains $M.DisplayName) { [pscustomobject]@{ error = 'The proxy address is already being used.'; OperationGuid = $R.OperationGuid }; continue }
            $M.EmailAddresses = $R.CmdletInput.Parameters.EmailAddresses
            $M.PrimarySmtpAddress = ($M.EmailAddresses | Where-Object { $_ -cmatch '^SMTP:' }) -replace '^SMTP:'
            [pscustomobject]@{ Success = $true; OperationGuid = $R.OperationGuid }
        }
    }

    foreach ($Name in 'Set-CIPPBulkEmailDomain', 'Invoke-ExecBulkEmailDomain') { . (& $Find "$Name.ps1") }
    $script:Users = { param([string[]]$Keys) @($Keys | ForEach-Object { [pscustomobject]@{ id = $script:Ids[$_]; userPrincipalName = "$_@jamessherratt.co.uk" } }) }
    $script:Mailbox = { param($Name) $script:Mailboxes | Where-Object DisplayName -eq $Name }
    $script:Request = { param($Body) @{ Params = @{ CIPPEndpoint = 'ExecBulkEmailDomain' }; Headers = @{}; Body = $Body } }
}

Describe 'Bulk email domain add-on' {
    BeforeEach { & $script:NewTenant }

    Describe 'Set-CIPPBulkEmailDomain' {
        It 'adds the address as an alias, keeping everything else' {
            $R = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode alias -Users (& $script:Users 'carly', 'dawn')
            @($R.Status) | Should -Be @('Changed', 'Changed')
            (& $script:Mailbox 'Carly Sherratt').EmailAddresses | Should -Be @('SMTP:carly@jamessherratt.co.uk', 'smtp:carly@sherrattbps.onmicrosoft.com', 'smtp:carly@sherrattsestates.com')
            (& $script:Mailbox 'Carly Sherratt').PrimarySmtpAddress | Should -Be 'carly@jamessherratt.co.uk'
            $script:Sent.Count | Should -Be 2
        }

        It 'makes it the primary address, keeping the old one and other addresses as aliases' {
            $R = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode primary -Users (& $script:Users 'james', 'dawn')
            @($R.Status) | Should -Be @('Changed', 'Changed')
            $J = & $script:Mailbox 'James Sherratt'
            $J.EmailAddresses[0] | Should -BeExactly 'SMTP:james@sherrattsestates.com'
            $J.EmailAddresses | Should -Contain 'smtp:james@jamessherratt.co.uk'
            $J.EmailAddresses | Should -Contain 'X500:/o=ExchangeLabs/cn=james'
            @($J.EmailAddresses | Where-Object { $_ -cmatch '^SMTP:' }).Count | Should -Be 1
            @($J.EmailAddresses | Where-Object { $_ -match 'james@sherrattsestates.com' }).Count | Should -Be 1
            $R[0].Message | Should -Match 'james@jamessherratt.co.uk stays as an alias'
            $R[1].Message | Should -Match '\(added\)'
        }

        It 'takes the name from the current email address by default, or from the sign-in name' {
            $null = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode alias -Users (& $script:Users 'carly')
            (& $script:Mailbox 'Carly Sherratt').EmailAddresses | Should -Contain 'smtp:carly@sherrattsestates.com'
            & $script:NewTenant
            $null = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode alias -NameFrom upn -Users (& $script:Users 'carly')
            (& $script:Mailbox 'Carly Sherratt').EmailAddresses | Should -Contain 'smtp:carly.sherratt@sherrattsestates.com'
        }

        It 'skips, with the reason: <Why>' -ForEach @(
            @{ Why = 'already has the alias'; Key = 'james'; Mode = 'alias'; Match = 'Already has james@sherrattsestates.com' }
            @{ Why = 'no mailbox'; Key = 'guest'; Mode = 'alias'; Match = 'No mailbox' }
            @{ Why = 'synced from on-premises'; Key = 'synced'; Mode = 'primary'; Match = 'on-premises' }
        ) {
            $R = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode $Mode -Users (& $script:Users $Key)
            $R.Status | Should -Be 'Skipped'
            $R.Message | Should -Match $Match
            $script:Sent.Count | Should -Be 0
        }

        It 'skips an address that already belongs to someone else' {
            $script:OtherRecipients[0].EmailAddresses = @('SMTP:dawn@sherrattsestates.com')
            $R = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode primary -Users (& $script:Users 'dawn')
            $R.Status | Should -Be 'Skipped'
            $R.Message | Should -Match 'already belongs to Dawn \(old contact\)'
        }

        It 'does nothing when the address is already primary' {
            $null = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode primary -Users (& $script:Users 'dawn')
            $script:Sent.Clear()
            $R = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode primary -Users (& $script:Users 'dawn')
            $R.Message | Should -Match 'already the primary address'
            $script:Sent.Count | Should -Be 0
        }

        It 'refuses a domain that is not verified in the tenant' {
            { Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'notyet.com' -Users (& $script:Users 'dawn') } | Should -Throw '*isn''t a verified domain*'
            { Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'contoso.com' -Users (& $script:Users 'dawn') } | Should -Throw '*isn''t a verified domain*'
            $script:Sent.Count | Should -Be 0
        }

        It 'reports a user Exchange refused, and carries on with the rest, in the order given' {
            $script:FailFor = @('Carly Sherratt')
            $R = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode alias -Users (& $script:Users 'dawn', 'carly', 'guest')
            @($R.Name) | Should -Be @('Dawn Lane', 'Carly Sherratt', 'guest@jamessherratt.co.uk')
            @($R.Status) | Should -Be @('Changed', 'Failed', 'Skipped')
            $R[1].Message | Should -Match 'already being used'
            (& $script:Mailbox 'Dawn Lane').EmailAddresses | Should -Contain 'smtp:dawn@sherrattsestates.com'
        }

        It 'logs each change' {
            $null = Set-CIPPBulkEmailDomain -TenantFilter 'jamessherratt.co.uk' -Domain 'sherrattsestates.com' -Mode primary -Users (& $script:Users 'dawn')
            $script:Logs | Should -Contain 'Set primary address of Dawn Lane to dawn@sherrattsestates.com (was dawn@jamessherratt.co.uk)'
        }
    }

    Describe 'Invoke-ExecBulkEmailDomain' {
        It 'returns a summary and a line per user' {
            $R = Invoke-ExecBulkEmailDomain -Request (& $script:Request @{ tenantFilter = 'jamessherratt.co.uk'; Domain = @{ value = 'sherrattsestates.com' }; Mode = 'primary'; Users = (& $script:Users 'james', 'dawn', 'guest') })
            $R.StatusCode | Should -Be 200
            $R.Body.Results[0] | Should -Be 'Made @sherrattsestates.com the primary address for 2 of 3 users; 1 skipped.'
            $R.Body.Results[1] | Should -Match '^James Sherratt: james@sherrattsestates.com is now the primary address'
            @($R.Body.Results).Count | Should -Be 4
        }
        It 'refuses bad input: <Why>' -ForEach @(
            @{ Why = 'All Tenants'; Body = @{ tenantFilter = 'AllTenants'; Domain = 'sherrattsestates.com'; Mode = 'alias'; Users = @(@{ id = '11111111-1111-1111-1111-111111111111' }) } }
            @{ Why = 'no domain'; Body = @{ tenantFilter = 'jamessherratt.co.uk'; Domain = ''; Mode = 'alias'; Users = @(@{ id = '11111111-1111-1111-1111-111111111111' }) } }
            @{ Why = 'a bad domain'; Body = @{ tenantFilter = 'jamessherratt.co.uk'; Domain = 'not a domain'; Mode = 'alias'; Users = @(@{ id = '11111111-1111-1111-1111-111111111111' }) } }
            @{ Why = 'an unknown mode'; Body = @{ tenantFilter = 'jamessherratt.co.uk'; Domain = 'sherrattsestates.com'; Mode = 'replace'; Users = @(@{ id = '11111111-1111-1111-1111-111111111111' }) } }
            @{ Why = 'an unknown name source'; Body = @{ tenantFilter = 'jamessherratt.co.uk'; Domain = 'sherrattsestates.com'; Mode = 'alias'; NameFrom = 'display'; Users = @(@{ id = '11111111-1111-1111-1111-111111111111' }) } }
            @{ Why = 'no users'; Body = @{ tenantFilter = 'jamessherratt.co.uk'; Domain = 'sherrattsestates.com'; Mode = 'alias'; Users = @() } }
            @{ Why = 'a user without an id'; Body = @{ tenantFilter = 'jamessherratt.co.uk'; Domain = 'sherrattsestates.com'; Mode = 'alias'; Users = @(@{ id = 'james' }) } }
        ) {
            (Invoke-ExecBulkEmailDomain -Request (& $script:Request $Body)).StatusCode | Should -Be 400
            $script:Sent.Count | Should -Be 0
        }
        It 'reports an unverified domain as a failure without changing anything' {
            $R = Invoke-ExecBulkEmailDomain -Request (& $script:Request @{ tenantFilter = 'jamessherratt.co.uk'; Domain = 'notyet.com'; Mode = 'alias'; Users = (& $script:Users 'dawn') })
            $R.StatusCode | Should -Be 500
            $R.Body.Results[0] | Should -Match "isn't a verified domain"
        }
    }
}
