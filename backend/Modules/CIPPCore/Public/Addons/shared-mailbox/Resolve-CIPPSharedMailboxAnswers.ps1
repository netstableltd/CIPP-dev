function Resolve-CIPPSharedMailboxAnswers {
    <#
    .SYNOPSIS
        The customer's answers to the shared mailbox questions, checked, with our recommendation for any
        question not answered.

    .PARAMETER Answers
        A hashtable or object of question id -> option id, for example @{ send = 'sendAs' }.

    .OUTPUTS
        An ordered hashtable with every question id.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param($Answers)

    $Options = Get-CIPPSharedMailboxOptions
    $Given = @{}
    if ($Answers -is [System.Collections.IDictionary]) { foreach ($K in $Answers.Keys) { $Given["$K"] = $Answers[$K] } }
    elseif ($Answers) { foreach ($P in $Answers.PSObject.Properties) { $Given[$P.Name] = $P.Value } }

    $Result = [ordered]@{}
    foreach ($Q in $Options.questions) {
        $Value = "$($Given[$Q.id])".Trim()
        if (-not $Value) {
            $Value = @($Q.options | Where-Object { $_.recommended } | Select-Object -First 1).id
        } elseif (@($Q.options.id) -notcontains $Value) {
            throw "'$Value' isn't an option for $($Q.title.ToLower()) ($($Q.id)): use $(@($Q.options.id) -join ', ')."
        }
        $Result[$Q.id] = $Value
    }
    $Result
}
