function Test-CIPPReportAccess {
    <#
    .SYNOPSIS
        Checks a Reports request against the caller's tenant access.

    .DESCRIPTION
        The Reports endpoints are 'AnyTenant' (they take the tenant in the body as TenantId), so CIPP's
        built-in tenant check does not run for them. This applies it: with -Tenant, the caller must have
        access to that tenant; with -AllTenants (global settings that affect every company), the caller
        must have access to all tenants. -Filter returns only the tenants (objects with customerId) the
        caller may see.

    .FUNCTIONALITY
        Internal
    #>
    [CmdletBinding(DefaultParameterSetName = 'Tenant')]
    param(
        [Parameter(Mandatory)]$Request,
        [Parameter(ParameterSetName = 'Tenant')]$Tenant,
        [Parameter(ParameterSetName = 'All')][switch]$AllTenants,
        [Parameter(ParameterSetName = 'Filter')][object[]]$Filter
    )

    $Allowed = @(Test-CIPPAccess -Request $Request -TenantList)
    $Everything = $Allowed -contains 'AllTenants'
    switch ($PSCmdlet.ParameterSetName) {
        'All' { return $Everything }
        'Filter' {
            if ($Everything) { return @($Filter) }
            return @($Filter | Where-Object { $_ -and ($Allowed -contains "$($_.customerId)" -or $Allowed -contains "$($_.TenantId)") })
        }
        default {
            if ($Everything) { return $true }
            return [bool]($Tenant -and ($Allowed -contains "$($Tenant.customerId)"))
        }
    }
}
