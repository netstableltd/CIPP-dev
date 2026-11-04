/** Pure helpers for the bulk email domain add-on (bulk-email-domain). */

const domainOf = (value) =>
  value?.domain?.value ?? value?.domain?.label ?? value?.domain ?? ''

/** The name before the @ that a user's new address will use. */
export const localPartFor = (user, nameFrom = 'email') => {
  const source =
    nameFrom === 'upn'
      ? user?.userPrincipalName
      : user?.mail || user?.userPrincipalName
  return String(source ?? '').split('@')[0]
}

/** The address a user will get, for the confirmation preview. */
export const newAddressFor = (user, value) => {
  const local = localPartFor(user, value?.nameFrom)
  const domain = domainOf(value)
  return local && domain ? `${local}@${domain}` : ''
}

export const isBulkEmailDomainReady = (value) =>
  Boolean(domainOf(value)) && ['alias', 'primary'].includes(value?.mode)

export const describeBulkEmailDomain = (value) => {
  const domain = domainOf(value)
  if (!isBulkEmailDomainReady(value)) return 'Not set'
  const what =
    value.mode === 'primary'
      ? `Add @${domain} and make it the primary email address`
      : `Add @${domain} as an alias`
  const name =
    value.nameFrom === 'upn' ? 'the sign-in name' : 'the current email address'
  return `${what} (name before the @ from ${name})`
}

/** The ExecBulkEmailDomain request for the selected users. */
export const bulkEmailDomainRequest = ({ value, users, tenant }) => ({
  url: '/api/ExecBulkEmailDomain',
  data: {
    tenantFilter: tenant,
    Domain: domainOf(value),
    Mode: value?.mode,
    NameFrom: value?.nameFrom === 'upn' ? 'upn' : 'email',
    Users: (users ?? []).map((u) => ({
      id: u.id,
      userPrincipalName: u.userPrincipalName,
    })),
  },
})
