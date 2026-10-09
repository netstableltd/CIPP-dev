function ConvertTo-AteraPurchaseRow {
    <#
    .SYNOPSIS
        Turns Atera invoices into one row per purchased item (products, product/service lines and expenses).

    .DESCRIPTION
        Atera invoices (GET /billing/invoices) mix labour, ticket lines and items sold. Only the items
        are purchases: line Product 'Product', 'Product/Service' or 'Expense'. Invoices carry no
        customer id, only the billed company name (To.CompanyName), so lines are matched on the Atera
        customer name, ignoring case and surrounding spaces.

        Row fields: id (InvoiceId-LineIdx), InvoiceDate, InvoiceNumber, Item (first line of the
        description), Details (the rest), Quantity, Rate, Total, Currency, LineType.

    .PARAMETER Invoices
        Invoices from the billing/invoices endpoint.

    .PARAMETER CustomerName
        The Atera customer name to keep.

    .PARAMETER Since
        Keep invoices dated on or after this (UTC).

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Invoices = @(),
        [Parameter(Mandatory)][string]$CustomerName,
        [datetime]$Since = [datetime]::MinValue
    )

    $Wanted = $CustomerName.Trim()
    foreach ($Invoice in $Invoices) {
        if ("$($Invoice.To.CompanyName)".Trim() -ine $Wanted) { continue }
        $Date = $null
        if ($Invoice.InvoiceDate -is [datetime]) { $Date = $Invoice.InvoiceDate.ToUniversalTime() }
        else {
            $Parsed = [datetime]::MinValue
            if ([datetime]::TryParse("$($Invoice.InvoiceDate)", [cultureinfo]::InvariantCulture, [System.Globalization.DateTimeStyles]'AssumeUniversal, AdjustToUniversal', [ref]$Parsed)) { $Date = $Parsed }
        }
        if (-not $Date -or $Date -lt $Since) { continue }
        foreach ($Line in @($Invoice.LineItems)) {
            if ("$($Line.Product)" -notin @('Product', 'Product/Service', 'Expense')) { continue }
            $Text = ("$($Line.Description)" -replace "`r", '').Trim()
            $Lines = @($Text -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
            [pscustomobject]@{
                id            = "$($Invoice.InvoiceId)-$($Line.LineIdx)"
                InvoiceDate   = $Date.ToString('yyyy-MM-ddTHH:mm:ssZ')
                InvoiceNumber = "$($Invoice.InvoiceNumberAsString)"
                Item          = $(if ($Lines.Count -gt 0) { $Lines[0] } else { "$($Line.Product)" })
                Details       = ($Lines | Select-Object -Skip 1) -join '; '
                Quantity      = [double]$Line.Quantity
                Rate          = [double]$Line.Rate
                Total         = [double]$Line.Total
                Currency      = "$($Invoice.Currency)"
                LineType      = "$($Line.Product)"
            }
        }
    }
}
