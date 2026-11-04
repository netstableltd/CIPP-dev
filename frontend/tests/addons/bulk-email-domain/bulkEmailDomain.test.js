import { describe, expect, it } from 'vitest'
import {
  bulkEmailDomainRequest,
  describeBulkEmailDomain,
  isBulkEmailDomainReady,
  localPartFor,
  newAddressFor,
} from '../../../src/addons/bulk-email-domain/bulkEmailDomain'
import {
  enabledAddonExtensions,
  userBulkEditExtensions,
} from '../../../src/utils/addon-extensions'

const carly = {
  id: 'c',
  displayName: 'Carly',
  userPrincipalName: 'carly.sherratt@jamessherratt.co.uk',
  mail: 'carly@jamessherratt.co.uk',
}

describe('bulk email domain helpers', () => {
  it('takes the name from the email address, falling back to the sign-in name, or from the sign-in name', () => {
    expect(localPartFor(carly)).toBe('carly')
    expect(localPartFor({ userPrincipalName: 'x@y.com' })).toBe('x')
    expect(localPartFor(carly, 'upn')).toBe('carly.sherratt')
  })

  it('previews the new address', () => {
    expect(
      newAddressFor(carly, { domain: { value: 'sherrattsestates.com' } })
    ).toBe('carly@sherrattsestates.com')
    expect(newAddressFor(carly, {})).toBe('')
  })

  it('is ready only with a domain and a mode', () => {
    expect(isBulkEmailDomainReady({ domain: { value: 'a.com' } })).toBe(false)
    expect(
      isBulkEmailDomainReady({ domain: { value: 'a.com' }, mode: 'primary' })
    ).toBe(true)
    expect(isBulkEmailDomainReady({ mode: 'alias' })).toBe(false)
  })

  it('describes the change for the confirmation step', () => {
    expect(
      describeBulkEmailDomain({
        domain: { value: 'a.com' },
        mode: 'primary',
        nameFrom: 'email',
      })
    ).toBe(
      'Add @a.com and make it the primary email address (name before the @ from the current email address)'
    )
    expect(
      describeBulkEmailDomain({
        domain: { value: 'a.com' },
        mode: 'alias',
        nameFrom: 'upn',
      })
    ).toMatch(/as an alias .*sign-in name/)
    expect(describeBulkEmailDomain({})).toBe('Not set')
  })

  it('builds the request with only the users’ ids and sign-in names', () => {
    expect(
      bulkEmailDomainRequest({
        value: { domain: { value: 'a.com' }, mode: 'alias' },
        users: [carly],
        tenant: 't.com',
      })
    ).toEqual({
      url: '/api/ExecBulkEmailDomain',
      data: {
        tenantFilter: 't.com',
        Domain: 'a.com',
        Mode: 'alias',
        NameFrom: 'email',
        Users: [{ id: 'c', userPrincipalName: carly.userPrincipalName }],
      },
    })
  })
})

describe('add-on extensions', () => {
  it('finds the add-on’s Edit Properties extension', () => {
    const e = userBulkEditExtensions.find(
      (x) => x.property === 'addonEmailDomain'
    )
    expect(e).toMatchObject({
      addonId: 'bulk-email-domain',
      isAddonExtension: true,
      singleTenant: true,
    })
  })

  it('hides the extensions of a turned-off add-on, and keeps them while flags load', () => {
    expect(
      enabledAddonExtensions(userBulkEditExtensions, undefined)
    ).toHaveLength(userBulkEditExtensions.length)
    expect(
      enabledAddonExtensions(userBulkEditExtensions, [
        { Id: 'Addon.bulk-email-domain', Enabled: false },
      ])
    ).toHaveLength(0)
    expect(
      enabledAddonExtensions(userBulkEditExtensions, [
        { Id: 'Addon.bulk-email-domain', Enabled: true },
        { Id: 'Other', Enabled: false },
      ])
    ).toHaveLength(userBulkEditExtensions.length)
  })
})
