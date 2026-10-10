function Resolve-CIPPReportOverrides {
    <#
    .SYNOPSIS
        Applies the manual changes made when reviewing a customer report draft to the pre-check findings.

    .DESCRIPTION
        A draft's overrides (saved on Reports > Review) change only what the customer sees:

          HiddenFindings  finding ids left out of the customer's recommendations
          FindingText     id -> replacement recommendation wording
          FindingItems    id -> replacement 'Affected' list (array or comma-separated text)
          Extra           added recommendations: @{ text; plan = $true for 'To plan for' }
          Note            the 'A note from your IT team' box on the summary page (used by the caller)
          HiddenSections  section ids left out this month (used by the caller)

        Internal-only findings (no customer wording) pass through untouched, so the pre-check is
        unaffected. Returns new finding objects; the input is not changed.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [object[]]$Findings = @(),
        $Overrides
    )

    $Get = {
        param($Name)
        if ($null -eq $Overrides) { return $null }
        if ($Overrides -is [System.Collections.IDictionary]) { return $Overrides[$Name] }
        if ($Overrides.PSObject.Properties.Name -contains $Name) { return $Overrides.$Name }
        $null
    }
    $Lookup = {
        param($Map, $Key)
        if ($null -eq $Map) { return $null }
        if ($Map -is [System.Collections.IDictionary]) { if ($Map.Contains($Key)) { return $Map[$Key] }; return $null }
        if ($Map.PSObject.Properties.Name -contains $Key) { return $Map.$Key }
        $null
    }

    $Hidden = @(& $Get 'HiddenFindings' | Where-Object { $_ } | ForEach-Object { "$_" })
    $Text = & $Get 'FindingText'
    $ItemsMap = & $Get 'FindingItems'

    $Out = foreach ($F in @($Findings)) {
        $Copy = [ordered]@{}
        foreach ($P in $F.PSObject.Properties) { $Copy[$P.Name] = $P.Value }
        if ($Copy.Customer) {
            if ($Hidden -contains "$($Copy.Id)") { $Copy.Customer = $null; $Copy.HiddenByReview = $true }
            else {
                $NewText = & $Lookup $Text "$($Copy.Id)"
                if ("$NewText".Trim()) { $Copy.Customer = "$NewText".Trim() }
                $NewItems = & $Lookup $ItemsMap "$($Copy.Id)"
                if ($null -ne $NewItems) {
                    $Copy.CustomerItems = @($(if ($NewItems -is [string]) { $NewItems -split '\s*,\s*' } else { @($NewItems) }) | ForEach-Object { "$_".Trim() } | Where-Object { $_ })
                }
            }
        }
        [pscustomobject]$Copy
    }

    $n = 0
    $Added = foreach ($E in @(& $Get 'Extra')) {
        $Wording = "$(& $Lookup $E 'text')".Trim()
        if (-not $Wording) { continue }
        $n++
        $Plan = [bool](& $Lookup $E 'plan')
        [pscustomobject]@{
            Id            = "manual-$n"
            Severity      = $(if ($Plan) { 'Info' } else { 'Fix' })
            Area          = 'Added in review'
            Title         = $Wording
            Detail        = 'Added when the report was reviewed.'
            Count         = 0
            Items         = @()
            Customer      = $Wording
            CustomerItems = @()
            Manual        = $true
        }
    }

    @(@($Out) + @($Added))
}
