function Push-AteraExtensionSync {
    <#
    .SYNOPSIS
        Orchestrator activity for the account-wide Atera sync (queued by Invoke-AteraExtensionScheduler
        or the Integrations > Atera > Force Sync button).
    .FUNCTIONALITY
        Entrypoint
    #>
    param($Item)

    $WindowDays = if ($Item.WindowDays) { [int]$Item.WindowDays } else { 45 }
    Invoke-AteraExtensionSync -WindowDays $WindowDays
    return $true
}
