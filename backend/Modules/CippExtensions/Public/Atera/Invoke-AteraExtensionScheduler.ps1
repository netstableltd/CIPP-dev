function Invoke-AteraExtensionScheduler {
    <#
    .SYNOPSIS
        Called by Start-ExtensionOrchestrator (every 2 hours). Queues the nightly account-wide
        Atera sync when one is due.

    .DESCRIPTION
        A sync is due when there has never been one, or the last one started more than 20 hours
        ago and it is currently night time (00:00-05:59 UTC). If the last sync is more than
        26 hours old it runs regardless of the hour, so a missed night is caught up.
        The sync runs as a single orchestrated activity (Push-AteraExtensionSync).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param([switch]$Force)

    $Table = Get-CIPPTable -TableName 'AteraSettings'
    $Last = Get-CIPPAzDataTableEntity @Table -Filter "PartitionKey eq 'Atera' and RowKey eq 'LastQueued'"
    $Now = (Get-Date).ToUniversalTime()
    $LastQueued = $null
    if ($Last.LastQueuedTime) { try { $LastQueued = ([datetime]$Last.LastQueuedTime).ToUniversalTime() } catch {} }

    $Due = $Force.IsPresent -or
        (-not $LastQueued) -or
        (($Now - $LastQueued).TotalHours -ge 20 -and $Now.Hour -lt 6) -or
        (($Now - $LastQueued).TotalHours -ge 26)

    if (-not $Due) {
        Write-Information "Atera sync not due (last queued $LastQueued UTC)"
        return
    }

    $InputObject = [PSCustomObject]@{
        OrchestratorName = 'AteraSyncOrchestrator'
        Priority         = 6
        AllowCollision   = $false
        Batch            = @([PSCustomObject]@{
                FunctionName = 'AteraExtensionSync'
                QueueName    = 'Atera Sync'
            })
    }
    $InstanceId = Start-CIPPOrchestrator -InputObject $InputObject
    Add-CIPPAzDataTableEntity @Table -Force -Entity @{
        PartitionKey   = 'Atera'
        RowKey         = 'LastQueued'
        LastQueuedTime = $Now.ToString('o')
        InstanceId     = "$InstanceId"
    }
    Write-Information "Queued Atera sync, orchestration $InstanceId"
    return $InstanceId
}
