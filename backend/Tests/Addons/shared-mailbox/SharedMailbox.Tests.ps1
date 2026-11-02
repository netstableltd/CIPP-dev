# Pester tests for the shared mailbox add-on (shared-mailbox): the question set, answers, the status reader,
# the setup (create, access through people or a group, sending, settings, signature rule, archive, sign-in),
# both PDFs, the endpoints, and the add-on guide kit (ExecAddonGuide). Exchange and Graph are faked in memory.

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
    function Write-LogMessage { param($headers, $API, $tenant, $message, $Sev, $LogData) }
    function Get-CippException { param($Exception) @{ NormalizedError = "$($Exception.Exception.Message ?? $Exception)" } }
    function Start-Sleep { param($Seconds) }
    function Get-CippReportTenantName { param($TenantFilter) 'Contoso Ltd' }
    function ConvertTo-CippReportPdf { param($Blocks, $Variables, $TenantName, $TenantFilter, $ReportName, $GeneratedOn) $script:Pdf = @{ Blocks = $Blocks; Variables = $Variables }; [byte[]](37, 80, 68, 70) }
    function Get-CIPPTable { param($TableName) @{ Context = $TableName } }
    function Add-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $script:Saved.Add([pscustomobject]$Entity) }
    function Get-CIPPAzDataTableEntity { param($Context, $Filter) @($script:Saved | Where-Object { $Filter -match "PartitionKey eq '$($_.PartitionKey)'" -and $Filter -match "RowKey eq '$($_.RowKey)'" }) }
    function Remove-CIPPAzDataTableEntity { param($Context, $Entity, [switch]$Force) $null = $script:Saved.Remove($Entity) }
    function Sync-CIPPMailboxPermissionCache { param($TenantFilter, $MailboxIdentity, $User, $PermissionType, $Action) }

    # ---- A fake tenant: users, one shared mailbox, groups, permissions, rules.
    $script:NewTenant = {
        $script:T = @{
            Users     = @{
                'jane@contoso.com' = [pscustomobject]@{ DisplayName = 'Jane Smith'; PrimarySmtpAddress = 'jane@contoso.com'; Name = 'jane'; Alias = 'jane'; RecipientTypeDetails = 'UserMailbox' }
                'tom@contoso.com'  = [pscustomobject]@{ DisplayName = 'Tom Jones'; PrimarySmtpAddress = 'tom@contoso.com'; Name = 'tom'; Alias = 'tom'; RecipientTypeDetails = 'UserMailbox' }
                'old@contoso.com'  = [pscustomobject]@{ DisplayName = 'Old Starter'; PrimarySmtpAddress = 'old@contoso.com'; Name = 'old'; Alias = 'old'; RecipientTypeDetails = 'UserMailbox' }
            }
            Mailboxes = @{}
            Groups    = @{}
            FullAccess = [System.Collections.Generic.List[object]]::new()
            SendAs    = [System.Collections.Generic.List[object]]::new()
            Rules     = [System.Collections.Generic.List[object]]::new()
            Accounts  = @{}
            Licences  = @{}
            Calls     = [System.Collections.Generic.List[object]]::new()
        }
    }
    $script:AddMailbox = {
        param($Address, $DisplayName = 'Info', $Type = 'SharedMailbox')
        $Id = [guid]::NewGuid().ToString()
        $script:T.Mailboxes[$Address] = [pscustomobject]@{
            DisplayName = $DisplayName; PrimarySmtpAddress = $Address; Name = ($Address -split '@')[0]; Alias = ($Address -split '@')[0]
            RecipientTypeDetails = $Type; ExternalDirectoryObjectId = $Id; EmailAddresses = @("SMTP:$Address")
            GrantSendOnBehalfTo = @(); MessageCopyForSentAsEnabled = $false; MessageCopyForSendOnBehalfEnabled = $false
            HiddenFromAddressListsEnabled = $false; RequireSenderAuthenticationEnabled = $false; ArchiveStatus = 'None'
            Language = 'en-US'; TimeZone = 'Pacific Standard Time'
        }
        $script:T.Accounts[$Id] = $true
        $script:T.Mailboxes[$Address]
    }
    $script:Recipient = {
        param($Who)
        $K = "$Who".ToLowerInvariant()
        if ($script:T.Users[$K]) { return $script:T.Users[$K] }
        if ($script:T.Mailboxes[$K]) { return $script:T.Mailboxes[$K] }
        $G = $script:T.Groups.Values | Where-Object { $_.PrimarySmtpAddress -eq $K -or $_.Name -eq $Who -or $_.DisplayName -eq $Who } | Select-Object -First 1
        if ($G) { return $G }
        $U = $script:T.Users.Values | Where-Object { $_.DisplayName -eq $Who -or $_.Name -eq $Who } | Select-Object -First 1
        $U
    }

    function New-ExoRequest {
        param($tenantid, $cmdlet, $cmdParams, $Select, $Anchor, $useSystemMailbox)
        $P = $cmdParams
        $script:T.Calls.Add([pscustomobject]@{ Cmdlet = $cmdlet; Params = $P })
        $Mbx = { $script:T.Mailboxes["$($P.Identity)".ToLowerInvariant()] }
        switch ($cmdlet) {
            'Get-Mailbox' {
                if ($P.RecipientTypeDetails) { return @($script:T.Mailboxes.Values | Where-Object RecipientTypeDetails -eq $P.RecipientTypeDetails) }
                $M = & $Mbx; if (-not $M) { throw "The operation couldn't be performed because object '$($P.Identity)' couldn't be found." }; return $M
            }
            'Get-Recipient' { $R = & $script:Recipient $P.Identity; if (-not $R) { throw "couldn't be found" }; return $R }
            'New-Mailbox' { return (& $script:AddMailbox $P.PrimarySmtpAddress $P.DisplayName) }
            'Set-Mailbox' {
                $M = & $Mbx
                foreach ($K in $P.Keys) {
                    switch ($K) {
                        'Identity' { }
                        'EmailAddresses' { $M.EmailAddresses = @($M.EmailAddresses) + @($P.EmailAddresses.Add | ForEach-Object { "smtp:$_" }) }
                        'GrantSendonBehalfTo' {
                            if ($P.GrantSendonBehalfTo.add) { $M.GrantSendOnBehalfTo = @($M.GrantSendOnBehalfTo) + @((& $script:Recipient $P.GrantSendonBehalfTo.add).DisplayName) }
                            if ($P.GrantSendonBehalfTo.remove) { $Name = (& $script:Recipient $P.GrantSendonBehalfTo.remove).DisplayName; $M.GrantSendOnBehalfTo = @($M.GrantSendOnBehalfTo | Where-Object { $_ -ne $Name }) }
                        }
                        'Confirm' { }
                        default { $M.$K = $P[$K] }
                    }
                }
                return
            }
            'Get-MailboxPermission' {
                return @([pscustomobject]@{ User = 'NT AUTHORITY\SELF'; AccessRights = @('FullAccess', 'ReadPermission'); IsInherited = $false; Deny = $false }) +
                    @($script:T.FullAccess | Where-Object Mailbox -eq "$($P.Identity)".ToLowerInvariant() | ForEach-Object { [pscustomobject]@{ User = $_.User; AccessRights = @('FullAccess'); IsInherited = $false; Deny = $false } })
            }
            'Add-MailboxPermission' { $script:T.FullAccess.Add([pscustomobject]@{ Mailbox = "$($P.Identity)".ToLowerInvariant(); User = "$($P.user)".ToLowerInvariant(); AutoMap = $P.automapping }); return }
            'Remove-MailboxPermission' { $Gone = @($script:T.FullAccess | Where-Object { $_.Mailbox -eq "$($P.Identity)".ToLowerInvariant() -and $_.User -eq "$($P.user)".ToLowerInvariant() }); foreach ($G in $Gone) { $null = $script:T.FullAccess.Remove($G) }; return }
            'Get-RecipientPermission' {
                return @([pscustomobject]@{ Trustee = 'NT AUTHORITY\SELF'; AccessRights = @('SendAs'); Deny = $false }) +
                    @($script:T.SendAs | Where-Object Mailbox -eq "$($P.Identity)".ToLowerInvariant() | ForEach-Object { [pscustomobject]@{ Trustee = $_.User; AccessRights = @('SendAs'); Deny = $false } })
            }
            'Add-RecipientPermission' { $script:T.SendAs.Add([pscustomobject]@{ Mailbox = "$($P.Identity)".ToLowerInvariant(); User = "$($P.Trustee)".ToLowerInvariant() }); return }
            'Remove-RecipientPermission' { $Gone = @($script:T.SendAs | Where-Object { $_.Mailbox -eq "$($P.Identity)".ToLowerInvariant() -and $_.User -eq "$($P.Trustee)".ToLowerInvariant() }); foreach ($G in $Gone) { $null = $script:T.SendAs.Remove($G) }; return }
            'Get-MailboxStatistics' { return [pscustomobject]@{ TotalItemSize = '1.5 GB (1,610,612,736 bytes)' } }
            'Get-MailboxRegionalConfiguration' { $M = & $Mbx; return [pscustomobject]@{ Language = $M.Language; TimeZone = $M.TimeZone } }
            'Set-MailboxRegionalConfiguration' { $M = & $Mbx; $M.Language = $P.Language; $M.TimeZone = $P.TimeZone; return }
            'Get-TransportRule' { return @($script:T.Rules) }
            'New-TransportRule' { $script:T.Rules.Add([pscustomobject]@{ Name = $P.Name; From = $P.From; Html = $P.ApplyHtmlDisclaimerText; State = 'Enabled' }); return }
            'Set-TransportRule' { ($script:T.Rules | Where-Object Name -eq $P.Identity).Html = $P.ApplyHtmlDisclaimerText; return }
            'Remove-TransportRule' { $R = $script:T.Rules | Where-Object Name -eq $P.Identity; $null = $script:T.Rules.Remove($R); return }
            'Get-DistributionGroup' { $G = & $script:Recipient $P.Identity; if (-not $G -or $G.RecipientTypeDetails -notmatch 'Group') { throw "couldn't be found" }; return $G }
            'New-DistributionGroup' { $G = [pscustomobject]@{ Name = $P.Name; DisplayName = $P.DisplayName; PrimarySmtpAddress = $P.PrimarySmtpAddress; Alias = $P.Alias; RecipientTypeDetails = 'MailUniversalSecurityGroup'; Members = [System.Collections.Generic.List[string]]::new() }; $script:T.Groups[$P.Name] = $G; return $G }
            'Set-DistributionGroup' { return }
            'Get-DistributionGroupMember' { $G = & $script:Recipient $P.Identity; return @($G.Members | ForEach-Object { [pscustomobject]@{ DisplayName = $script:T.Users[$_].DisplayName; PrimarySmtpAddress = $_; WindowsLiveID = $_ } }) }
            'Add-DistributionGroupMember' { (& $script:Recipient $P.Identity).Members.Add("$($P.Member)".ToLowerInvariant()); return }
            'Remove-DistributionGroupMember' { $null = (& $script:Recipient $P.Identity).Members.Remove("$($P.Member)".ToLowerInvariant()); return }
            'Enable-Mailbox' { (& $Mbx).ArchiveStatus = 'Active'; return }
            default { throw "Unexpected cmdlet $cmdlet" }
        }
    }
    function New-GraphGetRequest {
        param($uri, $tenantid, $noPagination)
        if ($uri -match '/users/([^/?]+)/licenseDetails') { return @($script:T.Licences[$Matches[1]]) | Where-Object { $_ } }
        if ($uri -match '/users/([^/?]+)') { return [pscustomobject]@{ accountEnabled = $script:T.Accounts[$Matches[1]]; onPremisesSyncEnabled = $false } }
        throw "Unexpected Graph GET $uri"
    }
    function New-GraphPOSTRequest {
        param($uri, $tenantid, $type, $body)
        if ($body -like '*"accountEnabled":false*' -and $uri -match '/users/([^/?]+)$') { $script:T.Accounts[$Matches[1]] = $false; return }
        throw "Unexpected Graph $type $uri"
    }

    foreach ($Name in 'Get-CIPPSharedMailboxOptions', 'Resolve-CIPPSharedMailboxAnswers', 'Get-CIPPSharedMailboxList', 'Get-CIPPSharedMailboxStatus', 'Get-CIPPSharedMailboxSignatureRuleName',
        'Set-CIPPSharedMailbox', 'Set-CIPPMailboxPermission', 'Build-CippSharedMailboxCustomerTree', 'Build-CippSharedMailboxSummaryTree', 'New-CippReportComponents',
        'Invoke-ListSharedMailboxSetup', 'Invoke-ExecSharedMailboxSetup', 'Invoke-ExecSharedMailboxCustomerPdf', 'Invoke-ExecSharedMailboxSummaryPdf',
        'Get-CIPPAddonGuide', 'Invoke-ExecAddonGuide', 'Get-CIPPAddonManifest', 'Test-CIPPAddonManifest', 'ConvertFrom-CIPPDocxGuide') {
        . (& $Find "$Name.ps1")
    }
    $script:Request = { param($Body, $Endpoint = 'ExecSharedMailboxSetup') @{ Params = @{ CIPPEndpoint = $Endpoint }; Headers = @{ 'x-ms-client-principal' = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes('{"userDetails":"admin@contoso.com"}')) }; Body = $Body; Query = @{} } }
    $script:Text = { param($Tree) ($Tree.Blocks | ConvertTo-Json -Depth 12) }
    $script:Step = { param($Result, $Step) @($Result.Steps | Where-Object Step -eq $Step) }
}

Describe 'Shared mailbox add-on' {
    BeforeEach {
        & $script:NewTenant
        $script:Saved = [System.Collections.Generic.List[object]]::new()
    }

    Describe 'The question set' {
        It 'has eight questions, each with exactly one recommended option and full explanations' {
            $Q = @((Get-CIPPSharedMailboxOptions).questions)
            $Q.Count | Should -Be 8
            foreach ($Question in $Q) {
                @($Question.options | Where-Object recommended).Count | Should -Be 1 -Because $Question.id
                foreach ($O in $Question.options) {
                    $O.summary | Should -Not -BeNullOrEmpty -Because "$($Question.id)/$($O.id)"
                    @($O.pros).Count | Should -BeGreaterThan 0 -Because "$($Question.id)/$($O.id)"
                    $O.suits | Should -Not -BeNullOrEmpty
                }
            }
        }
        It 'fills unanswered questions with the recommendation' {
            $A = Resolve-CIPPSharedMailboxAnswers -Answers @{ send = 'sendOnBehalf' }
            $A.send | Should -Be 'sendOnBehalf'
            $A.grantVia | Should -Be 'people'
            $A.sentItems | Should -Be 'shared'
            $A.Keys.Count | Should -Be 8
        }
        It 'refuses an option that does not exist' {
            { Resolve-CIPPSharedMailboxAnswers -Answers @{ send = 'telepathy' } } | Should -Throw "*isn't an option for sending*"
        }
    }

    Describe 'Set-CIPPSharedMailbox' {
        It 'creates a mailbox with everything we recommend for two people' {
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -New @{ DisplayName = 'Info'; Address = 'info@contoso.com'; Aliases = @('hello@contoso.com') } -People 'jane@contoso.com', 'tom@contoso.com' -Answers @{}
            (& $script:Step $R 'Mailbox').Status | Should -Be 'Success'
            $M = $script:T.Mailboxes['info@contoso.com']
            $M.EmailAddresses | Should -Contain 'smtp:hello@contoso.com'
            $script:T.Accounts[$M.ExternalDirectoryObjectId] | Should -BeFalse
            $M.Language | Should -Be 'en-GB'
            $M.TimeZone | Should -Be 'GMT Standard Time'
            @($script:T.FullAccess | Where-Object Mailbox -eq 'info@contoso.com').User | Should -Be @('jane@contoso.com', 'tom@contoso.com')
            @($script:T.FullAccess.AutoMap | Select-Object -Unique) | Should -Be @($true)
            @($script:T.SendAs.User) | Should -Be @('jane@contoso.com', 'tom@contoso.com')
            $M.MessageCopyForSentAsEnabled | Should -BeTrue
            $M.MessageCopyForSendOnBehalfEnabled | Should -BeTrue
            $M.HiddenFromAddressListsEnabled | Should -BeFalse
            @($R.Steps | Where-Object Status -eq 'Error') | Should -BeNullOrEmpty
        }

        It 'turns automapping off when people add it as a separate account' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{ outlook = 'account' }
            $script:T.FullAccess[0].AutoMap | Should -BeFalse
        }

        It 'refuses an address that belongs to someone else, and a mailbox that is not shared' {
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -New @{ DisplayName = 'Jane'; Address = 'jane@contoso.com' } -Answers @{}
            (& $script:Step $R 'Mailbox').Status | Should -Be 'Error'
            & $script:AddMailbox 'boss@contoso.com' 'Boss' 'UserMailbox' | Out-Null
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'boss@contoso.com' -Answers @{}
            (& $script:Step $R 'Mailbox').Message | Should -Match 'not a shared mailbox'
            $script:T.Calls.Cmdlet | Should -Not -Contain 'Add-MailboxPermission'
        }

        It 'uses an existing shared mailbox at the new address as it is' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -New @{ DisplayName = 'Info'; Address = 'info@contoso.com' } -Answers @{}
            (& $script:Step $R 'Mailbox').Status | Should -Be 'Info'
            $script:T.Calls.Cmdlet | Should -Not -Contain 'New-Mailbox'
        }

        It 'gives access through a group: makes the group, adds the people, grants the group' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com', 'tom@contoso.com' -Answers @{ grantVia = 'group' }
            $G = $script:T.Groups['SG-Mailbox-info']
            $G | Should -Not -BeNullOrEmpty
            @($G.Members) | Should -Be @('jane@contoso.com', 'tom@contoso.com')
            @($script:T.FullAccess.User) | Should -Be @('sg-mailbox-info@contoso.com')
            $script:T.FullAccess[0].AutoMap | Should -BeFalse
            @($script:T.SendAs.User) | Should -Be @('sg-mailbox-info@contoso.com')
            @($R.Steps | Where-Object Status -eq 'Error') | Should -BeNullOrEmpty
        }

        It 'switches Send As to Send on behalf rather than granting both' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{}
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{ send = 'sendOnBehalf' }
            $script:T.SendAs.Count | Should -Be 0
            $script:T.Mailboxes['info@contoso.com'].GrantSendOnBehalfTo | Should -Be @('Jane Smith')
        }

        It 'changes nothing the second time' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{}
            $script:T.Calls.Clear()
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{}
            @($script:T.Calls.Cmdlet | Where-Object { $_ -match '^(Add|Remove|Set|New|Enable)-' }) | Should -BeNullOrEmpty
            @($R.Steps | Where-Object Status -eq 'Success') | Should -BeNullOrEmpty
        }

        It 'leaves other people alone unless asked, then takes their access away' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $script:T.FullAccess.Add([pscustomobject]@{ Mailbox = 'info@contoso.com'; User = 'old@contoso.com'; AutoMap = $true })
            $script:T.SendAs.Add([pscustomobject]@{ Mailbox = 'info@contoso.com'; User = 'old@contoso.com' })
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{}
            $script:T.FullAccess.User | Should -Contain 'old@contoso.com'
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{} -RemoveOthers $true
            @($script:T.FullAccess.User) | Should -Be @('jane@contoso.com')
            @($script:T.SendAs.User) | Should -Be @('jane@contoso.com')
        }

        It 're-grants Full Access when asked, so automapping follows the choice' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $script:T.FullAccess.Add([pscustomobject]@{ Mailbox = 'info@contoso.com'; User = 'jane@contoso.com'; AutoMap = $true })
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{ outlook = 'account' } -ReapplyAccess $true
            @($script:T.FullAccess).Count | Should -Be 1
            $script:T.FullAccess[0].AutoMap | Should -BeFalse
        }

        It 'applies the address book, outside email and sent-copy choices' {
            & $script:AddMailbox 'scans@contoso.com' 'Scans' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'scans@contoso.com' -Answers @{ visibility = 'hidden'; external = 'internal'; sentItems = 'personal'; send = 'none' }
            $M = $script:T.Mailboxes['scans@contoso.com']
            $M.HiddenFromAddressListsEnabled | Should -BeTrue
            $M.RequireSenderAuthenticationEnabled | Should -BeTrue
            $M.MessageCopyForSentAsEnabled | Should -BeFalse
        }

        It 'adds, updates and removes the signature rule' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -Answers @{ signature = 'rule' }
            (& $script:Step $R 'Signature').Status | Should -Be 'Warning'
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -Answers @{ signature = 'rule' } -SignatureHtml '<p>Info team</p>'
            $script:T.Rules[0].Name | Should -Be 'Shared mailbox signature - info@contoso.com'
            $script:T.Rules[0].From | Should -Be 'info@contoso.com'
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -Answers @{ signature = 'rule' } -SignatureHtml '<p>New</p>'
            $script:T.Rules[0].Html | Should -Be '<p>New</p>'
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -Answers @{ signature = 'manual' }
            $script:T.Rules.Count | Should -Be 0
        }

        It 'turns the archive on only with a licence, and says what is needed without one' {
            $M = & $script:AddMailbox 'info@contoso.com'
            $R = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -Answers @{ size = 'licensed' } -EnableArchive $true
            (& $script:Step $R 'Licence').Message | Should -Match 'Exchange Online Plan 1'
            $M.ArchiveStatus | Should -Be 'None'
            $script:T.Licences[$M.ExternalDirectoryObjectId] = [pscustomobject]@{ skuPartNumber = 'EXCHANGESTANDARD'; servicePlans = @([pscustomobject]@{ servicePlanName = 'EXCHANGE_S_STANDARD'; provisioningStatus = 'Success' }) }
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -Answers @{ size = 'licensed' } -EnableArchive $true
            $M.ArchiveStatus | Should -Be 'Active'
        }
    }

    Describe 'Get-CIPPSharedMailboxStatus' {
        It 'reads access, settings and the answers they amount to' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{ visibility = 'hidden'; signature = 'rule' } -SignatureHtml 'x'
            $S = Get-CIPPSharedMailboxStatus -TenantFilter 'contoso.com' -Identity 'info@contoso.com'
            $S.Exists | Should -BeTrue
            $S.IsShared | Should -BeTrue
            $S.FullAccess.Name | Should -Be 'Jane Smith'
            @($S.SendAs | ForEach-Object { $_.Address }) | Should -Be @('jane@contoso.com')
            $S.SignInBlocked | Should -BeTrue
            $S.SizeBytes | Should -Be 1610612736
            $S.Current.grantVia | Should -Be 'people'
            $S.Current.send | Should -Be 'sendAs'
            $S.Current.visibility | Should -Be 'hidden'
            $S.Current.signature | Should -Be 'rule'
            $S.Current.outlook | Should -BeNullOrEmpty
            $S.Current.size | Should -Be 'standard'
        }
        It 'says when there is no such mailbox' {
            (Get-CIPPSharedMailboxStatus -TenantFilter 'contoso.com' -Identity 'nope@contoso.com').Exists | Should -BeFalse
        }
        It 'reports the access group and its members' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'tom@contoso.com' -Answers @{ grantVia = 'group' }
            $S = Get-CIPPSharedMailboxStatus -TenantFilter 'contoso.com' -Identity 'info@contoso.com'
            $S.Group.Name | Should -Be 'SG-Mailbox-info'
            @($S.Group.Members | ForEach-Object { $_.Address }) | Should -Be @('tom@contoso.com')
            $S.Current.grantVia | Should -Be 'group'
        }
    }

    Describe 'The PDFs' {
        It 'customer PDF: every question, every option, the recommendation and the reply list' {
            $Tree = Build-CippSharedMailboxCustomerTree -TenantName 'Contoso Ltd' -MailboxName 'info@contoso.com' -ContactName 'Sam' -PreparedBy 'Dave'
            $J = & $script:Text $Tree
            foreach ($Q in (Get-CIPPSharedMailboxOptions).questions) {
                $J | Should -Match ([regex]::Escape($Q.question))
                foreach ($O in $Q.options) { $J | Should -Match ([regex]::Escape($O.label)) }
            }
            $J | Should -Match 'Send as the mailbox \(recommended\)'
            $J | Should -Match 'Your reply'
            $J | Should -Match 'Dear Sam'
            $J | Should -Match 'Microsoft 365 group'
            $Tree.Variables.coversubtitle | Should -Match 'info@contoso.com'
        }
        It 'summary PDF: how it is set up and a guide matched to the choices' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Set-CIPPSharedMailbox -TenantFilter 'contoso.com' -Identity 'info@contoso.com' -People 'jane@contoso.com' -Answers @{}
            $S = Get-CIPPSharedMailboxStatus -TenantFilter 'contoso.com' -Identity 'info@contoso.com'
            $J = & $script:Text (Build-CippSharedMailboxSummaryTree -TenantName 'Contoso Ltd' -Status $S -Answers @{})
            $J | Should -Match 'Jane Smith'
            $J | Should -Match 'Nothing to do'
            $J | Should -Match 'Options \\u003e From|Options > From'
            $J | Should -Not -Match 'Still to do'
            $J2 = & $script:Text (Build-CippSharedMailboxSummaryTree -TenantName 'Contoso Ltd' -Status $S -Answers @{ outlook = 'account'; signature = 'rule'; send = 'sendOnBehalf' })
            $J2 | Should -Match 'File \\u003e Add Account|File > Add Account'
            $J2 | Should -Match 'on behalf of'
            $J2 | Should -Match 'automatic signature isn'
        }
        It 'summary PDF: flags a mailbox nobody can use yet and a missing licence' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $S = Get-CIPPSharedMailboxStatus -TenantFilter 'contoso.com' -Identity 'info@contoso.com'
            $J = & $script:Text (Build-CippSharedMailboxSummaryTree -TenantName 'Contoso Ltd' -Status $S -Answers @{ size = 'licensed' })
            $J | Should -Match 'Nobody has access yet'
            $J | Should -Match 'needs an Exchange Online licence'
        }
    }

    Describe 'Endpoints' {
        It 'lists the questions and shared mailboxes, or one mailbox''s status' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $R = Invoke-ListSharedMailboxSetup -Request (& $script:Request @{ tenantFilter = 'contoso.com' } 'ListSharedMailboxSetup')
            $R.StatusCode | Should -Be 200
            @($R.Body.Options.questions).Count | Should -Be 8
            @($R.Body.Mailboxes | ForEach-Object { $_.Address }) | Should -Be @('info@contoso.com')
            $R = Invoke-ListSharedMailboxSetup -Request (& $script:Request @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com' } 'ListSharedMailboxSetup')
            $R.Body.Status.Exists | Should -BeTrue
            (Invoke-ListSharedMailboxSetup -Request (& $script:Request @{ tenantFilter = 'AllTenants' } 'ListSharedMailboxSetup')).StatusCode | Should -Be 400
        }
        It 'refuses bad input: <Why>' -ForEach @(
            @{ Why = 'no mailbox'; Body = @{ tenantFilter = 'contoso.com' } }
            @{ Why = 'a bad address'; Body = @{ tenantFilter = 'contoso.com'; New = @{ DisplayName = 'Info'; Address = 'not an address' } } }
            @{ Why = 'no name'; Body = @{ tenantFilter = 'contoso.com'; New = @{ DisplayName = ''; Address = 'info@contoso.com' } } }
            @{ Why = 'a bad person'; Body = @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com'; People = @('jane') } }
            @{ Why = 'an unknown option'; Body = @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com'; Answers = @{ grantVia = 'magic' } } }
            @{ Why = 'a bad group name'; Body = @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com'; GroupName = "x'; drop" } }
            @{ Why = 'All Tenants'; Body = @{ tenantFilter = 'AllTenants'; Identity = 'info@contoso.com' } }
        ) {
            (Invoke-ExecSharedMailboxSetup -Request (& $script:Request $Body)).StatusCode | Should -Be 400
            $script:T.Calls.Cmdlet | Should -Not -Contain 'New-Mailbox'
        }
        It 'creates a mailbox from the page''s request and returns the steps and status' {
            $R = Invoke-ExecSharedMailboxSetup -Request (& $script:Request @{
                    tenantFilter = 'contoso.com'
                    New          = @{ DisplayName = 'Accounts'; Address = 'accounts@contoso.com'; Aliases = @() }
                    People       = @(@{ value = 'jane@contoso.com'; label = 'Jane' })
                    Answers      = @{ send = 'sendAs' }
                })
            $R.StatusCode | Should -Be 200
            $R.Body.Address | Should -Be 'accounts@contoso.com'
            @($R.Body.Status.FullAccess | ForEach-Object { $_.Address }) | Should -Be @('jane@contoso.com')
            @($R.Body.Results).Count | Should -BeGreaterThan 3
        }
        It 'makes both PDFs' {
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $R = Invoke-ExecSharedMailboxCustomerPdf -Request (& $script:Request @{ tenantFilter = 'contoso.com'; MailboxName = 'info@contoso.com' } 'ExecSharedMailboxCustomerPdf')
            $R.StatusCode | Should -Be 200
            $R.ContentType | Should -Be 'application/pdf'
            $R = Invoke-ExecSharedMailboxSummaryPdf -Request (& $script:Request @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com'; Answers = @{} } 'ExecSharedMailboxSummaryPdf')
            $R.StatusCode | Should -Be 200
            $R.Headers.'Content-Disposition' | Should -Match 'Shared_mailbox_info_contoso_com'
            (Invoke-ExecSharedMailboxSummaryPdf -Request (& $script:Request @{ tenantFilter = 'contoso.com'; Identity = 'nope@contoso.com' } 'ExecSharedMailboxSummaryPdf')).StatusCode | Should -Be 400
        }
    }

    Describe 'Add-on guides (ExecAddonGuide)' {
        BeforeAll {
            # A minimal Word document: a title, a heading and a paragraph.
            $script:Docx = {
                Add-Type -AssemblyName System.IO.Compression
                $Xml = '<?xml version="1.0" encoding="UTF-8"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>' +
                '<w:p><w:pPr><w:pStyle w:val="Title"/></w:pPr><w:r><w:t>Sending from a shared mailbox</w:t></w:r></w:p>' +
                '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr><w:r><w:t>Steps from our own guide</w:t></w:r></w:p>' +
                '<w:p><w:r><w:t>In a new email, choose Options then From.</w:t></w:r></w:p></w:body></w:document>'
                $Ms = [System.IO.MemoryStream]::new()
                $Zip = [System.IO.Compression.ZipArchive]::new($Ms, [System.IO.Compression.ZipArchiveMode]::Create, $true)
                foreach ($E in @(@('[Content_Types].xml', '<?xml version="1.0"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"/>'), @('word/document.xml', $Xml))) {
                    $W = [System.IO.StreamWriter]::new($Zip.CreateEntry($E[0]).Open()); $W.Write($E[1]); $W.Dispose()
                }
                $Zip.Dispose()
                , $Ms.ToArray()
            }
        }
        It 'saves a guide listed in the add-on''s manifest, and it reaches the summary PDF' {
            $Data = [Convert]::ToBase64String((& $script:Docx))
            $R = Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'shared-mailbox'; Key = 'sending'; Action = 'Upload'; FileName = 'C:\fakepath\Send As.docx'; Data = $Data } 'ExecAddonGuide')
            $R.StatusCode | Should -Be 200
            $R.Body.Guide.FileName | Should -Be 'Send As.docx'
            $G = Get-CIPPAddonGuide -AddonId 'shared-mailbox' -Key 'sending' -IncludeFile
            $G.Title | Should -Be 'Sending from a shared mailbox'
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $null = Invoke-ExecSharedMailboxSummaryPdf -Request (& $script:Request @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com' } 'ExecSharedMailboxSummaryPdf')
            ($script:Pdf.Blocks | ConvertTo-Json -Depth 12) | Should -Match 'Steps from our own guide'
        }
        It 'leaves the guide out when asked' {
            $null = Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'shared-mailbox'; Key = 'sending'; Action = 'Upload'; FileName = 'g.docx'; Data = [Convert]::ToBase64String((& $script:Docx)) } 'ExecAddonGuide')
            & $script:AddMailbox 'info@contoso.com' | Out-Null
            $script:Pdf = $null
        (Invoke-ExecSharedMailboxSummaryPdf -Request (& $script:Request @{ tenantFilter = 'contoso.com'; Identity = 'info@contoso.com'; IncludeGuide = $false } 'ExecSharedMailboxSummaryPdf')).StatusCode | Should -Be 200
            ($script:Pdf.Blocks | ConvertTo-Json -Depth 12) | Should -Not -Match 'Steps from our own guide'
        }
        It 'refuses a guide the add-on does not list, an add-on that is not installed, and a non-Word file' {
            (Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'shared-mailbox'; Key = 'other'; Action = 'Remove' } 'ExecAddonGuide')).StatusCode | Should -Be 400
            (Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'no-such-addon'; Key = 'sending'; Action = 'Remove' } 'ExecAddonGuide')).StatusCode | Should -Be 404
            (Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'shared-mailbox'; Key = 'sending'; Action = 'Upload'; FileName = 'g.pdf'; Data = 'AAAA' } 'ExecAddonGuide')).StatusCode | Should -Be 400
            $script:Saved.Count | Should -Be 0
        }
        It 'removes the guide' {
            $null = Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'shared-mailbox'; Key = 'sending'; Action = 'Upload'; FileName = 'g.docx'; Data = [Convert]::ToBase64String((& $script:Docx)) } 'ExecAddonGuide')
            (Invoke-ExecAddonGuide -Request (& $script:Request @{ AddonId = 'shared-mailbox'; Key = 'sending'; Action = 'Remove' } 'ExecAddonGuide')).StatusCode | Should -Be 200
            Get-CIPPAddonGuide -AddonId 'shared-mailbox' -Key 'sending' | Should -BeNullOrEmpty
        }
    }
}
