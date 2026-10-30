import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import {
  CippClaudeConnectorProcess,
  claudeConnectorProgress,
  claudeConnectorApplyBody,
} from '../../../src/addons/claude-m365/CippClaudeConnectorProcess'
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

const app = (key, over = {}) => ({
  Key: key,
  Name: `M365 MCP ${key} for Claude`,
  AppId: key === 'Client' ? '08ad6f98' : '07c030f6',
  Exists: true,
  Consented: false,
  ConsentUrl: `https://login.microsoftonline.com/t/adminconsent?client_id=${key}`,
  AssignmentRequired: false,
  Assigned: [],
  ...over,
})
const status = (apps, over = {}) => ({
  Tenant: 'contoso.com',
  Apps: apps,
  Group: { Name: 'SG-Claude-Users', Exists: false, Members: [] },
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

describe('claudeConnectorProgress', () => {
  it('starts at adding the apps', () => {
    expect(
      claudeConnectorProgress(
        status([app('Client', { Exists: false }), app('Server')])
      ).active
    ).toBe(0)
  })
  it('moves to consent, then choosing people, then done', () => {
    expect(
      claudeConnectorProgress(status([app('Client'), app('Server')])).active
    ).toBe(1)
    const consented = status([
      app('Client', { Consented: true }),
      app('Server', { Consented: true }),
    ])
    expect(claudeConnectorProgress(consented).active).toBe(2)
    const done = status([
      app('Client', {
        Consented: true,
        AssignmentRequired: true,
        Assigned: [{ PrincipalId: 'g' }],
      }),
      app('Server', {
        Consented: true,
        AssignmentRequired: true,
        Assigned: [{ PrincipalId: 'g' }],
      }),
    ])
    expect(claudeConnectorProgress(done)).toMatchObject({
      restricted: true,
      active: 3,
    })
  })
  it('does not count assignment required with nobody assigned', () => {
    const s = status([
      app('Client', { Consented: true, AssignmentRequired: true }),
      app('Server', { Consented: true, AssignmentRequired: true }),
    ])
    expect(claudeConnectorProgress(s).restricted).toBe(false)
  })
})

describe('claudeConnectorApplyBody', () => {
  it('sends user ids and the options', () => {
    expect(
      claudeConnectorApplyBody('contoso.com', {
        users: [{ value: 'u1', label: 'A' }],
        groupName: '  ',
        assignDirect: false,
        lockConsent: true,
      })
    ).toEqual({
      tenantFilter: 'contoso.com',
      Action: 'Apply',
      Users: ['u1'],
      GroupName: 'SG-Claude-Users',
      AssignUsersDirectly: false,
      LockUserConsent: true,
      RemoveOtherDirect: false,
    })
  })
})

describe('CippClaudeConnectorProcess', () => {
  beforeEach(() => vi.clearAllMocks())

  it('asks for a tenant when All Tenants is selected', () => {
    setup(undefined)
    renderWithProviders(<CippClaudeConnectorProcess tenant="AllTenants" />)
    expect(screen.getByText(/Choose a tenant/)).toBeInTheDocument()
  })

  it('adds the apps in a fresh tenant and keeps Apply disabled', () => {
    setup(
      status([
        app('Client', { Exists: false }),
        app('Server', { Exists: false }),
      ])
    )
    renderWithProviders(<CippClaudeConnectorProcess tenant="contoso.com" />)
    fireEvent.click(screen.getByRole('button', { name: 'Add the Claude apps' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecClaudeConnector',
      data: { tenantFilter: 'contoso.com', Action: 'AddApps' },
    })
    expect(screen.getByRole('button', { name: 'Apply' })).toBeDisabled()
  })

  it('opens the consent page in a pop-up', () => {
    setup(status([app('Client'), app('Server')]))
    const open = vi.spyOn(window, 'open').mockImplementation(() => null)
    renderWithProviders(<CippClaudeConnectorProcess tenant="contoso.com" />)
    fireEvent.click(
      screen.getByRole('button', { name: /Approve M365 MCP Client for Claude/ })
    )
    expect(open).toHaveBeenCalledWith(
      'https://login.microsoftonline.com/t/adminconsent?client_id=Client',
      'consent-Client',
      expect.stringContaining('popup')
    )
    open.mockRestore()
  })

  it('applies once consent is given and people are chosen', () => {
    setup(
      status([
        app('Client', { Consented: true }),
        app('Server', { Consented: true }),
      ])
    )
    renderWithProviders(<CippClaudeConnectorProcess tenant="contoso.com" />)
    expect(
      screen.getByRole('button', { name: /Client: consent given/ })
    ).toBeInTheDocument()
    const applyButton = screen.getByRole('button', { name: 'Apply' })
    expect(applyButton).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'pick Jo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecClaudeConnector',
      data: expect.objectContaining({
        Action: 'Apply',
        Users: ['u-jo'],
        GroupName: 'SG-Claude-Users',
        LockUserConsent: true,
      }),
    })
  })

  it('switches to direct assignment when the tenant has no Entra ID P1', () => {
    setup(
      status(
        [
          app('Client', { Consented: true }),
          app('Server', { Consented: true }),
        ],
        { EntraP1: false }
      )
    )
    renderWithProviders(<CippClaudeConnectorProcess tenant="contoso.com" />)
    fireEvent.click(screen.getByRole('button', { name: 'pick Jo' }))
    fireEvent.click(screen.getByRole('button', { name: 'Apply' }))
    expect(mutate.mock.calls.at(-1)[0].data.AssignUsersDirectly).toBe(true)
    expect(
      screen.getByText(/no, so people are assigned one by one/)
    ).toBeInTheDocument()
  })
})
