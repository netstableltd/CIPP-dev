function Get-CIPPPasswordHandoverSettings {
    <#
    .SYNOPSIS
        The password hand-over add-on's settings: the saved ones (table AddonSettings, row
        password-handover / settings) over the defaults in Config/Addons/password-handover.

    .OUTPUTS
        Hashtable: expireAfterDays, expireAfterViews, passphrase (email or none), retrievalStep, mustChange,
        signInUrl, subject, message, placeholders, and Saved (true once someone has saved their own).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if (-not $script:CIPPPasswordHandoverDefaults) {
        $Root = if ($env:CIPPRootPath) { $env:CIPPRootPath } else { Join-Path $PSScriptRoot '../../../../..' }
        $script:CIPPPasswordHandoverDefaults = Get-Content -Path (Join-Path $Root 'Config/Addons/password-handover/PasswordHandoverDefaults.json') -Raw | ConvertFrom-Json
    }
    $Defaults = $script:CIPPPasswordHandoverDefaults
    $Keys = 'expireAfterDays', 'expireAfterViews', 'passphrase', 'retrievalStep', 'mustChange', 'signInUrl', 'subject', 'message'

    $Settings = @{ Saved = $false; placeholders = @($Defaults.placeholders) }
    foreach ($Key in $Keys) { $Settings[$Key] = $Defaults.$Key }

    $Saved = $null
    try {
        $Table = Get-CIPPTable -TableName 'AddonSettings'
        $Row = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'password-handover' and RowKey eq 'settings'" | Select-Object -First 1
        if ($Row.Settings) { $Saved = $Row.Settings | ConvertFrom-Json -ErrorAction Stop }
    } catch {
        Write-LogMessage -API 'PasswordHandover' -message "Couldn't read the saved password hand-over settings, using the defaults: $($_.Exception.Message)" -Sev 'Warning'
    }
    if ($Saved) {
        foreach ($Key in $Keys) {
            if ($null -ne $Saved.$Key -and "$($Saved.$Key)" -ne '') { $Settings[$Key] = $Saved.$Key }
        }
        $Settings.Saved = $true
    }
    $Settings.expireAfterDays = [int]$Settings.expireAfterDays
    $Settings.expireAfterViews = [int]$Settings.expireAfterViews
    $Settings.retrievalStep = [bool]$Settings.retrievalStep
    $Settings.mustChange = [bool]$Settings.mustChange
    $Settings
}
