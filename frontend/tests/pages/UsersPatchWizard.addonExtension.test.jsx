import React from 'react'
import { screen, waitFor, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../test-utils'
import { api, getResult, postResult } from '../mocks/api-call'

// The Users bulk edit wizard (Edit Properties) with the fork's add-on extension point: an add-on's
// property shows in the list, is sent to the add-on's own endpoint and never to PatchUser, ordinary
// properties still go to PatchUser as before, and a turned-off add-on's property disappears.

vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
vi.mock('next/router', () => ({
  useRouter: () => ({ query: {}, push: vi.fn() }),
}))
vi.mock('../../src/components/CippTable/CippDataTable', () => ({
  CippDataTable: ({ title }) => <div>{title}</div>,
}))
// The add-on's own files are loaded by the require.context polyfill during test setup, before this file's
// mocks apply, so the domain picker can't be mocked under them. Wrap the add-on's real input with a
// button that fills in the domain instead.
vi.mock('../../src/utils/addon-extensions', async (importOriginal) => {
  const real = await importOriginal()
  const withPick = (RealInput) => {
    const Input = (props) => (
      <>
        <button
          type="button"
          onClick={() =>
            props.formControl.setValue(`${props.name}.domain`, {
              value: 'sherrattsestates.com',
              label: 'sherrattsestates.com',
            })
          }
        >
          Pick Email domain
        </button>
        <RealInput {...props} />
      </>
    )
    return Input
  }
  return {
    ...real,
    userBulkEditExtensions: real.userBulkEditExtensions.map((e) => ({
      ...e,
      Input: withPick(e.Input),
    })),
  }
})

import Page from '../../src/pages/identity/administration/users/patch-wizard.jsx'

const users = [
  {
    id: 'u1',
    displayName: 'Carly Sherratt',
    userPrincipalName: 'carly@jamessherratt.co.uk',
    mail: 'carly@jamessherratt.co.uk',
    Tenant: 'jamessherratt.co.uk',
  },
  {
    id: 'u2',
    displayName: 'Dawn Lane',
    userPrincipalName: 'dawn@jamessherratt.co.uk',
    mail: 'dawn@jamessherratt.co.uk',
    Tenant: 'jamessherratt.co.uk',
  },
]
const emptyGet = getResult()
const flagsOn = getResult({
  data: [{ Id: 'Addon.bulk-email-domain', Enabled: true }],
})
const flagsOff = getResult({
  data: [{ Id: 'Addon.bulk-email-domain', Enabled: false }],
})
const post = postResult()

const start = async (flags = flagsOn) => {
  api.get = (opts) => (opts?.url === '/api/ListFeatureFlags' ? flags : emptyGet)
  api.post = post
  post.mutate.mockClear()
  sessionStorage.setItem('patchWizardUsers', JSON.stringify(users))
  const user = userEvent.setup()
  renderWithProviders(<Page />)
  await user.click(await screen.findByRole('button', { name: 'Next Step' }))
  return user
}
const pick = async (user, label) => {
  await user.click(screen.getByLabelText('Properties to update'))
  await user.click(await screen.findByRole('option', { name: label }))
  await user.keyboard('{Escape}')
}

describe('Users bulk edit wizard: add-on properties', () => {
  it('offers the add-on property and sends it only to the add-on endpoint', async () => {
    const user = await start()
    await pick(user, 'Email Domain (Alias or Primary Address)')
    await user.click(await screen.findByRole('button', { name: 'Pick Email domain' }))
    await user.click(
      screen.getByRole('radio', { name: /make it the primary email address/ })
    )
    expect(
      screen.getByText(/Carly Sherratt gets carly@sherrattsestates.com/)
    ).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Next Step' }))

    expect(
      await screen.findByText(
        /Add @sherrattsestates.com and make it the primary email address/
      )
    ).toBeInTheDocument()
    await user.click(screen.getByRole('button', { name: 'Submit' }))
    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    expect(post.mutate).toHaveBeenCalledWith({
      url: '/api/ExecBulkEmailDomain',
      data: {
        tenantFilter: 'jamessherratt.co.uk',
        Domain: 'sherrattsestates.com',
        Mode: 'primary',
        NameFrom: 'email',
        Users: users.map((u) => ({
          id: u.id,
          userPrincipalName: u.userPrincipalName,
        })),
      },
    })
  })

  it('still sends ordinary properties to PatchUser, without the add-on property', async () => {
    const user = await start()
    await pick(user, 'Job Title')
    await pick(user, 'Email Domain (Alias or Primary Address)')
    await user.type(screen.getByLabelText('Job Title'), 'Negotiator')
    await user.click(await screen.findByRole('button', { name: 'Pick Email domain' }))
    await user.click(screen.getByRole('button', { name: 'Next Step' }))
    await user.click(await screen.findByRole('button', { name: 'Submit' }))

    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(2))
    const calls = post.mutate.mock.calls.map(([c]) => c)
    const patch = calls.find((c) => c.url === '/api/PatchUser')
    expect(patch.data).toEqual([
      { id: 'u1', tenantFilter: 'jamessherratt.co.uk', jobTitle: 'Negotiator' },
      { id: 'u2', tenantFilter: 'jamessherratt.co.uk', jobTitle: 'Negotiator' },
    ])
    expect(
      calls.find((c) => c.url === '/api/ExecBulkEmailDomain').data.Mode
    ).toBe('alias')
  })

  it('needs the domain before it can submit', async () => {
    const user = await start()
    await pick(user, 'Email Domain (Alias or Primary Address)')
    await user.click(screen.getByRole('button', { name: 'Next Step' }))
    expect(await screen.findByRole('button', { name: 'Submit' })).toBeDisabled()
  })

  it('hides the property when the add-on is turned off', async () => {
    const user = await start(flagsOff)
    await user.click(screen.getByLabelText('Properties to update'))
    const list = await screen.findByRole('listbox')
    expect(
      within(list).queryByRole('option', {
        name: 'Email Domain (Alias or Primary Address)',
      })
    ).toBeNull()
    expect(
      within(list).getByRole('option', { name: 'UPN Domain Suffix' })
    ).toBeInTheDocument()
  })
})
