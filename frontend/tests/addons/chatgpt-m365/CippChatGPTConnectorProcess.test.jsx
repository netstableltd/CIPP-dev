import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import {
  CippChatGPTConnectorProcess,
  chatgptConnectorProgress,
  chatgptConnectorApplyBody,
} from '../../../src/addons/chatgpt-m365/CippChatGPTConnectorProcess'
import { ApiGetCall, ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))
// The real picker loads users from Graph; this one picks Jo.
vi.mock('../../../src/components/CippComponents/CippFormUserSelector', () => ({
  CippFormUserSelector: ({ formControl, name }) => (
    <button
      type="button"
      onClick={() =>
        formControl.setValue(name, [
          { value: 'u-jo', label: 'Jo (jo@contoso.com)' },
        ])
      }
    >
      pick Jo
    </button>
  ),
}))

const app = (over = {}) => ({
  Key: 'ChatGPT',
  Name: 'ChatGPT',
  AppId: 'e0476654-c1d5-430b-ab80-70cbd947616a',
  Exists: true,
  Consented: false,
  AssignmentRequired: false,
  Assigned: [],
  OtherGrants: [],
  ...over,
})
const status = (apps, over = {}) => ({
  Tenant: 'contoso.com',
  Apps: apps,
  Group: { Name: 'SG-ChatGPT-Users', Exists: false, Members: [] },
  EntraP1: true,
  UserConsent: { Allowed: true, ManagedByCipp: false },
  AdminConsentRequests: { Enabled: false, GlobalAdminsReview: false },
  ...over,
})

let mutate
const setup = (data) => {
  ApiGetCall.mockReturnValue({
    data,
    isLoading: false,
    isFetching: false,
    isError: false,
    refetch: vi.fn(),
  })
  mutate = vi.fn()
  ApiPostCall.mockReturnValue({
    mutate,
    reset: vi.fn(),
    isPending: false,
    isError: false,
    data: undefined,
  })
}

describe('chatgptConnectorProgress', () => {
  it('starts at adding the app', () => {
    expect(
      chatgptConnectorProgress(status([app({ Exists: false })])).active
    ).toBe(0)
  })
  it('moves to choosing people (no consent step), then access, then done', () => {
    expect(chatgptConnectorProgress(status([app()])).active).toBe(1)
    const restricted = status([
      app({ AssignmentRequired: true, Assigned: [{ PrincipalId: 'g' }] }),
    ])
    expect(chatgptConnectorProgress(restricted)).toMatchObject({
      restricted: true,
      consented: false,
      active: 2,
    })
    const done = status(
      [
        app({
          Consented: true,
          AssignmentRequired: true,
          Assigned: [{ PrincipalId: 'g' }],
        }),
      ],
      { Access: { Level: 'read', TenantScopes: ['User.Read'] } }
    )
    expect(chatgptConnectorProgress(done)).toMatchObject({
      accessSet: true,
      active: 3,
    })
  })
  it('does not count full access from ChatGPT as access set', () => {
    const s = status(
      [
        app({
          Consented: true,
          AssignmentRequired: true,
          Assigned: [{ PrincipalId: 'g' }],
        }),
      ],
      { Access: { Level: 'full', TenantScopes: ['Mail.Send'] } }
    )
    expect(chatgptConnectorProgress(s).accessSet).toBe(false)
  })
  it('does not count assignment required with nobody assigned', () => {
    const s = status([app({ Consented: true, AssignmentRequired: true })])
    expect(chatgptConnectorProgress(s).restricted).toBe(false)
  })
})
describe('chatgptConnectorApplyBody', () => {
  it('sends user ids and the options', () => {
    expect(
      chatgptConnectorApplyBody('contoso.com', {
        users: [{ value: 'u1', label: 'A' }],
        groupName: '  ',
        assignDirect: false,
        lockConsent: true,
      })
    ).toEqual({
      tenantFilter: 'contoso.com',
      Action: 'Apply',
      Users: ['u1'],
      GroupName: 'SG-ChatGPT-Users',
      AssignUsersDirectly: false,
      LockUserConsent: true,
      RemoveOtherDirect: false,
    })
  })
})

describe('CippChatGPTConnectorProcess', () => {
  beforeEach(() => vi.clearAllMocks())

  it('asks for a tenant when All Tenants is selected', () => {
    setup(undefined)
    renderWithProviders(<CippChatGPTConnectorProcess tenant="AllTenants" />)
    expect(screen.getByText(/Choose a tenant/)).toBeInTheDocument()
  })

  it('adds the app in a fresh tenant and keeps Apply disabled', () => {
    setup(status([app({ Exists: false })]))
    renderWithProviders(<CippChatGPTConnectorProcess tenant="contoso.com" />)
    fireEvent.click(screen.getByRole('button', { name: 'Add the ChatGPT app' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecChatGPTConnector',
      data: { tenantFilter: 'contoso.com', Action: 'AddApps' },
    })
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })

  it('has no consent pop-up step', () => {
    setup(status([app()]))
    renderWithProviders(<CippChatGPTConnectorProcess tenant="contoso.com" />)
    expect(screen.queryByText(/Approve Microsoft's consent page/)).toBeNull()
    expect(screen.getByText('Match it in ChatGPT')).toBeInTheDocument()
  })

  it('applies before consent once people are chosen', () => {
    setup(status([app()]))
    renderWithProviders(<CippChatGPTConnectorProcess tenant="contoso.com" />)
    const applyButton = screen.getByRole('button', { name: 'Apply' })
    expect(applyButton).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'pick Jo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecChatGPTConnector',
      data: expect.objectContaining({
        Action: 'Apply',
        Users: ['u-jo'],
        GroupName: 'SG-ChatGPT-Users',
        LockUserConsent: true,
      }),
    })
  })

  it('switches to direct assignment when the tenant has no Entra ID P1', () => {
    setup(status([app({ Consented: true })], { EntraP1: false }))
    renderWithProviders(<CippChatGPTConnectorProcess tenant="contoso.com" />)
    fireEvent.click(screen.getByRole('button', { name: 'pick Jo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(mutate.mock.calls.at(-1)[0].data.AssignUsersDirectly).toBe(true)
    expect(
      screen.getByText(/no, so people are assigned one by one/)
    ).toBeInTheDocument()
  })

  it('shows self-approvals and other grants', () => {
    setup(
      status(
        [
          app({
            Consented: true,
            OtherGrants: [
              {
                Resource: 'Office 365 SharePoint Online',
                ConsentType: 'Principal',
                User: 'sam@contoso.com',
                Scopes: ['MyFiles.Read', 'AllSites.Read'],
              },
            ],
          }),
        ],
        {
          Access: {
            Level: 'read',
            TenantScopes: ['User.Read'],
            ReadAreas: [],
            People: [
              { UserId: 'u-sam', Upn: 'sam@contoso.com', Name: 'Sam', Level: 'read', SelfApproved: true },
            ],
          },
        }
      )
    )
    renderWithProviders(<CippChatGPTConnectorProcess tenant="contoso.com" />)
    expect(
      screen.getByText(/Approved ChatGPT for themselves: sam@contoso.com/)
    ).toBeInTheDocument()
    expect(
      screen.getByText(/Office 365 SharePoint Online \(MyFiles.Read, AllSites.Read, approved by sam@contoso.com\)/)
    ).toBeInTheDocument()
  })
})