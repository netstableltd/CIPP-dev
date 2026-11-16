// Password hand-over add-on: plain helpers for the settings page (no React), kept in step with
// Format-CIPPPasswordHandoverMessage and Test-CIPPPasswordHandoverSettings on the server.

// "Monday 30 November 2026", as the server writes it (Intl adds a comma after the weekday).
const ukDate = (date) =>
  `${date.toLocaleDateString('en-GB', { weekday: 'long' })} ${date.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'long',
    year: 'numeric',
  })}`

/** Fills in the message placeholders the way the server does; unknown ones are left as they are. */
export const fillHandoverMessage = (template, settings, sample = {}) => {
  const expires = new Date(sample.today ?? Date.now())
  expires.setDate(expires.getDate() + Number(settings.expireAfterDays || 0))
  const values = {
    displayName: sample.displayName ?? 'Jane Smith',
    userPrincipalName: sample.userPrincipalName ?? 'jane@contoso.com',
    link: sample.link ?? 'https://pwpush.example/p/abc123/r',
    views: String(settings.expireAfterViews ?? ''),
    expiryDate: ukDate(expires),
    signInUrl: settings.signInUrl ?? '',
    passphraseLine:
      settings.passphrase === 'email'
        ? ' When the page asks for a passphrase, enter the email address the password is for.'
        : '',
    mustChangeLine: settings.mustChange
      ? ' You will be asked to choose your own password straight away.'
      : '',
  }
  return String(template ?? '').replace(/\{([A-Za-z]+)\}/g, (match, key) =>
    key in values ? values[key] : match
  )
}

/** What's wrong with the settings, in words, or null when they can be saved. */
export const handoverSettingsProblem = (s) => {
  const days = Number(s.expireAfterDays)
  const views = Number(s.expireAfterViews)
  if (!Number.isInteger(days) || days < 1 || days > 90)
    return 'The link can last from 1 to 90 days.'
  if (!Number.isInteger(views) || views < 1 || views > 100)
    return 'The link can be opened from 1 to 100 times.'
  if (!/^https:\/\/[^\s<>"]{3,200}$/.test(String(s.signInUrl ?? '').trim()))
    return 'The sign-in address must start with https://.'
  const subject = String(s.subject ?? '').trim()
  if (!subject || subject.length > 200) return 'Give a subject of up to 200 characters.'
  const message = String(s.message ?? '')
  if (!message.trim() || message.length > 5000)
    return 'Give a message of up to 5,000 characters.'
  if (!message.includes('{link}'))
    return 'The message must include {link}, or the customer gets no link.'
  return null
}

/** The settings as the server takes them. */
export const handoverSettingsBody = (s) => ({
  Settings: {
    expireAfterDays: Number(s.expireAfterDays),
    expireAfterViews: Number(s.expireAfterViews),
    passphrase: s.passphrase === 'email' ? 'email' : 'none',
    retrievalStep: Boolean(s.retrievalStep),
    mustChange: Boolean(s.mustChange),
    signInUrl: String(s.signInUrl ?? '').trim(),
    subject: String(s.subject ?? '').trim(),
    message: String(s.message ?? ''),
  },
})
