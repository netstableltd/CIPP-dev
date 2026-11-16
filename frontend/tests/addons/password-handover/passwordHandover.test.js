import { describe, it, expect } from 'vitest'
import fs from 'fs'
import path from 'path'
import {
  fillHandoverMessage,
  handoverSettingsBody,
  handoverSettingsProblem,
} from '../../../src/addons/password-handover/passwordHandover'
import { userActions } from '../../../src/addons/password-handover/userActions'
import { userActionExtensions, withAddonUserActions } from '../../../src/utils/addon-extensions'

const Defaults = JSON.parse(
  fs.readFileSync(
    path.resolve(
      __dirname,
      '../../../../backend/Config/Addons/password-handover/PasswordHandoverDefaults.json'
    ),
    'utf8'
  )
)

describe('password hand-over helpers', () => {
  it('fills in the default message like the server does', () => {
    const text = fillHandoverMessage(Defaults.message, Defaults, {
      today: '2026-11-16T12:00:00Z',
      link: 'https://pw.example.com/p/x',
    })
    expect(text).toContain('Jane Smith (jane@contoso.com)')
    expect(text).toContain('https://pw.example.com/p/x')
    expect(text).toContain('opened 7 times')
    expect(text).toContain('Monday 30 November 2026')
    expect(text).toContain('enter the email address')
    expect(text).toContain('choose your own password')
    expect(text).not.toMatch(/\{(link|views|expiryDate|passphraseLine|mustChangeLine)\}/)
  })

  it('leaves unknown placeholders and drops sentences that do not apply', () => {
    const text = fillHandoverMessage('{link} {other}{passphraseLine}{mustChangeLine}', {
      ...Defaults,
      passphrase: 'none',
      mustChange: false,
    })
    expect(text).toBe('https://pwpush.example/p/abc123/r {other}')
  })

  it('accepts the defaults and says what is wrong with bad settings', () => {
    expect(handoverSettingsProblem(Defaults)).toBeNull()
    expect(handoverSettingsProblem({ ...Defaults, expireAfterDays: 0 })).toMatch(/1 to 90 days/)
    expect(handoverSettingsProblem({ ...Defaults, expireAfterViews: 101 })).toMatch(/1 to 100/)
    expect(handoverSettingsProblem({ ...Defaults, signInUrl: 'http://x.com' })).toMatch(/https/)
    expect(handoverSettingsProblem({ ...Defaults, message: 'Hello' })).toMatch(/\{link\}/)
  })

  it('sends numbers and only the two passphrase choices', () => {
    const body = handoverSettingsBody({ ...Defaults, expireAfterDays: '3', passphrase: 'other' })
    expect(body.Settings.expireAfterDays).toBe(3)
    expect(body.Settings.passphrase).toBe('none')
    expect(body.Settings).not.toHaveProperty('placeholders')
  })
})

describe('user actions extension point', () => {
  it('finds the add-on action', () => {
    const found = userActionExtensions.find((a) => a.addonId === 'password-handover')
    expect(found?.url).toBe('/api/ExecPasswordHandover')
  })

  it('places an add-on action after the named action, guarded by its permissions', () => {
    const allowed = (perms) => perms.includes('Identity.User.ReadWrite')
    const list = withAddonUserActions(
      [{ label: 'View User' }, { label: 'Reset Password' }, { label: 'Delete User' }],
      userActions.map((a) => ({ ...a, addonId: 'password-handover' })),
      allowed
    )
    expect(list.map((a) => a.label)).toEqual([
      'View User',
      'Reset Password',
      'Reset Password and Send Link',
      'Delete User',
    ])
    expect(list[2].condition()).toBe(true)
    expect(list[2]).not.toHaveProperty('permissions')
    expect(list[2]).not.toHaveProperty('after')
  })

  it('puts an action at the end when the named one is missing, and hides it without permission', () => {
    const list = withAddonUserActions(
      [{ label: 'View User' }],
      [{ label: 'X', url: '/api/X', after: 'Nope', permissions: ['Other.Thing'] }],
      () => false
    )
    expect(list.map((a) => a.label)).toEqual(['View User', 'X'])
    expect(list[1].condition()).toBe(false)
  })
})
