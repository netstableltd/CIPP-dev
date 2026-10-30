function Get-CIPPLatestCippVersion {
    <#
    .SYNOPSIS
        The newest upstream CIPP version (CyberDrain/CIPP main), cached for an hour. $null when it can't be fetched.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param()

    if ($script:CIPPLatestVersion -and $script:CIPPLatestVersionAt -gt (Get-Date).AddHours(-1)) { return $script:CIPPLatestVersion }
    try {
        $Text = "$(Invoke-CIPPRestMethod -Uri 'https://raw.githubusercontent.com/CyberDrain/CIPP/main/backend/version_latest.txt')".Trim()
        if ($Text -match '^v?(\d+\.\d+\.\d+)') {
            $script:CIPPLatestVersion = $Matches[1]
            $script:CIPPLatestVersionAt = Get-Date
            return $script:CIPPLatestVersion
        }
    } catch {
        Write-Information "Couldn't fetch the latest CIPP version: $($_.Exception.Message)"
    }
    $null
}
