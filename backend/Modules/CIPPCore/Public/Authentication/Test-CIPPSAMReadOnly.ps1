function Test-CIPPSAMReadOnly {
    <#
    .SYNOPSIS
        Returns $true when this instance must treat the CIPP-SAM app registration as read-only.

    .DESCRIPTION
        Set the app setting CIPP_SAM_READONLY=true on an instance that borrows its CIPP-SAM
        credentials (application ID, secret, refresh token, certificate) from another CIPP
        instance - typically a dev or staging copy that should see the same tenants as
        production.

        Every instance runs a weekly Update Tokens timer that rotates the SAM application
        secret and certificate when they near expiry, and reconciles (removes) SAM key
        credentials it does not recognise. Each instance only stores the new credential in its
        own Key Vault, so with two instances on one SAM app the one that did not rotate is left
        holding a credential that later expires - and the reconcile step could remove the other
        instance's certificate outright. With this flag set the instance still refreshes its own
        refresh token (stored only in its own vault) but never creates, renews or removes
        credentials on the shared app registration. The owning instance remains responsible
        for rotation; re-copy the rotated credentials to the read-only instance afterwards.

    .EXAMPLE
        if (Test-CIPPSAMReadOnly) { return }
    #>
    [CmdletBinding()]
    [OutputType([bool])]
    param()

    return ($env:CIPP_SAM_READONLY -eq 'true')
}
