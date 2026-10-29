import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, within } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import {
  CippClaudeAccessStep,
  claudeAccessDefaults,
  claudeAccessBody,
} from '../../../src/components/CippCommunity/CippClaudeAccessStep'
import {
  CippClaudeCustomerInfo,
  claudeReadinessItems,
} from '../../../src/components/CippCommunity/CippClaudeCustomerInfo'
import { claudeCurrentUsers } from '../../../src/components/CippCommunity/CippClaudeConnectorProcess'
import { ApiPostCall } from '../../../src/api/ApiCall'
import { downloadServerPdf } from '../../../src/components/CippPdf/useServerPdf'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))
vi.mock('../../../src/components/CippComponents/CippFormUserSelector', () => ({
  CippFormUserSelector: ({ formControl, name }) => (
    <button
      type="button"
      onClick={() =>
        formControl.setValue(name, { value: 'u-sam', label: 'Sam' })
      }
    >
      pick {name}
    </button>
  ),
}))
vi.mock('../../../src/components/CippPdf/useServerPdf', () => ({
  useServerPdf: vi.fn(() => ({
    pdfUrl: '',
    loading: false,
    error: null,
    download: vi.fn(),
  })),
  downloadServerPdf: vi.fn(() => Promise.resolve()),
  ServerPdfPane: () => <div>pdf pane</div>,
}))

const LEVELS = [
  {
    id: 'read',
    number: 1,
    name: 'Read only',
    tagline: 'Research',
    risk: 'Low',
    scopes: [],
  },
  {
    id: 'drafts',
    number: 2,
    name: 'Drafts and tidy-up',
    tagline: 'Prepares',
    risk: 'Low to medium',
    scopes: ['Mail.ReadWrite'],
  },
  {
    id: 'assistant',
    number: 3,
    name: 'Personal assistant',
    tagline: 'Acts',
    risk: 'Medium to high',
    scopes: ['Mail.Send'],
  },
  {
    id: 'full',
    number: 4,
    name: 'Full access',
    tagline: 'Keys',
    risk: 'High',
    scopes: ['Files.ReadWrite.All'],
  },
]
const AREAS = [
  { id: 'mail', label: 'Email', noun: 'email', description: 'Read email.' },
  {
    id: 'teams',
    label: 'Teams chats and channels',
    noun: 'Teams chats and channels',
    description: 'Read chats.',
  },
]
const status = (access) => ({
  Options: { Levels: LEVELS, ReadAreas: AREAS },
  Access: access,
})

let mutate
beforeEach(() => {
  vi.clearAllMocks()
  mutate = vi.fn()
  ApiPostCall.mockReturnValue({
    mutate,
    isPending: false,
    isError: false,
    data: undefined,
    reset: vi.fn(),
  })
})

describe('claudeAccessDefaults', () => {
  it('starts at read only when consent approved everything', () => {
    const d = claudeAccessDefaults(
      status({
        TenantScopes: ['Mail.Read'],
        ReadAreas: ['mail'],
        Level: 'full',
        People: [],
      })
    )
    expect(d.tenantLevel).toBe('read')
    expect(d.areas).toEqual({ mail: true, teams: false })
  })
  it('keeps a level that was chosen, and people with their own level', () => {
    const d = claudeAccessDefaults(
      status({
        TenantScopes: ['x'],
        ReadAreas: ['mail', 'teams'],
        Level: 'drafts',
        People: [
          { UserId: 'u1', Name: 'Jo', Upn: 'jo@c.com', Level: 'assistant' },
        ],
      })
    )
    expect(d.tenantLevel).toBe('drafts')
    expect(d.people).toEqual([
      { user: { value: 'u1', label: 'Jo (jo@c.com)' }, level: 'assistant' },
    ])
  })
  it('turns every area on when nothing is known yet', () => {
    expect(claudeAccessDefaults(status({})).areas).toEqual({
      mail: true,
      teams: true,
    })
  })
})

describe('claudeAccessBody', () => {
  it('sends areas, level and people, and removes people taken off the list', () => {
    const body = claudeAccessBody(
      'contoso.com',
      {
        areas: { mail: true, teams: false },
        tenantLevel: 'read',
        people: [
          { user: { value: 'u2' }, level: 'drafts' },
          { user: null, level: 'full' },
        ],
      },
      status({
        People: [
          { UserId: 'u1', Level: 'assistant' },
          { UserId: 'u2', Level: 'full' },
        ],
      })
    )
    expect(body).toEqual({
      tenantFilter: 'contoso.com',
      Action: 'Access',
      ReadAreas: ['mail'],
      TenantLevel: 'read',
      PeopleLevels: [
        { User: 'u2', Level: 'drafts' },
        { User: 'u1', Level: 'read' },
      ],
    })
  })
})

describe('claudeCurrentUsers', () => {
  it('uses group members, else people assigned directly', () => {
    expect(
      claudeCurrentUsers({
        Group: {
          Exists: true,
          Members: [{ Id: 'u1', Name: 'Jo', Upn: 'jo@c.com' }],
        },
      })
    ).toEqual([{ value: 'u1', label: 'Jo (jo@c.com)' }])
    expect(
      claudeCurrentUsers({
        Group: { Exists: false },
        Apps: [
          {
            Key: 'Server',
            Assigned: [
              { PrincipalId: 'u2', Name: 'Sam', Type: 'User' },
              { PrincipalId: 'g', Type: 'Group' },
            ],
          },
        ],
      })
    ).toEqual([{ value: 'u2', label: 'Sam' }])
  })
})

describe('CippClaudeAccessStep', () => {
  it('warns when everyone has everything, and saves the chosen access', () => {
    renderWithProviders(
      <CippClaudeAccessStep
        tenant="contoso.com"
        status={status({
          TenantScopes: ['Mail.Read'],
          ReadAreas: ['mail', 'teams'],
          Level: 'full',
          People: [],
        })}
      />
    )
    expect(screen.getByText(/Everyone currently has/)).toHaveTextContent(
      'Level 4: Full access'
    )
    expect(
      screen.getByText(/so everyone\s+can currently send email/)
    ).toBeInTheDocument()
    expect(
      screen.getByRole('radio', { name: /Level 1: Read only/ })
    ).toBeChecked()
    fireEvent.click(
      screen.getByRole('radio', { name: /Level 2: Drafts and tidy-up/ })
    )
    fireEvent.click(
      screen.getByRole('switch', { name: /Teams chats and channels/ })
    )
    fireEvent.click(screen.getByRole('button', { name: 'Add a person' }))
    fireEvent.click(screen.getByRole('button', { name: 'pick people.0.user' }))
    fireEvent.click(screen.getByRole('button', { name: 'Save access' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecClaudeConnector',
      data: {
        tenantFilter: 'contoso.com',
        Action: 'Access',
        ReadAreas: ['mail'],
        TenantLevel: 'drafts',
        PeopleLevels: [{ User: 'u-sam', Level: 'drafts' }],
      },
    })
  })

  it('needs at least one read area, and consent', () => {
    const { unmount } = renderWithProviders(
      <CippClaudeAccessStep
        tenant="contoso.com"
        status={status({
          TenantScopes: ['x'],
          ReadAreas: ['mail'],
          Level: 'read',
          People: [],
        })}
      />
    )
    fireEvent.click(screen.getByRole('switch', { name: /Email/ }))
    expect(
      screen.getByText('Choose at least one thing Claude can read.')
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save access' })).toBeDisabled()
    unmount()
    renderWithProviders(
      <CippClaudeAccessStep tenant="contoso.com" status={status({})} disabled />
    )
    expect(screen.getByRole('button', { name: 'Save access' })).toBeDisabled()
  })
})

describe('claudeReadinessItems', () => {
  it('describes what the tenant has', () => {
    const items = claudeReadinessItems({
      Backup: {
        Found: true,
        Barracuda: true,
        Products: ['Barracuda Cloud-to-Cloud Backup'],
      },
      EntraP1: false,
      Defender: { Found: true, Products: ['Microsoft Defender for Business'] },
      Suite: null,
      BusinessPremium: false,
    })
    expect(items.map((i) => [i.key, i.have])).toEqual([
      ['backup', true],
      ['p1', false],
      ['defender', true],
      ['bp', false],
    ])
    expect(items[0].detail).toBe('Barracuda backup found')
  })
  it('says when something could not be checked', () => {
    expect(claudeReadinessItems(undefined).every((i) => i.have === null)).toBe(
      true
    )
  })
})

describe('CippClaudeCustomerInfo', () => {
  it('shows the checks and downloads the PDF with the names', () => {
    renderWithProviders(
      <CippClaudeCustomerInfo
        tenant="contoso.com"
        tenantName="Contoso Ltd"
        readiness={{
          Backup: { Found: false, Barracuda: false, Products: [] },
          EntraP1: true,
          Defender: { Found: false, Products: [] },
          Suite: 'Microsoft 365 Business Premium',
          BusinessPremium: true,
        }}
      />
    )
    const box = screen.getByLabelText('Information for the customer')
    expect(
      within(box).getByText(
        /Third-party backup: No Barracuda or other backup app found/
      )
    ).toBeInTheDocument()
    expect(
      within(box).getByText(/Business Premium: Microsoft 365 Business Premium/)
    ).toBeInTheDocument()
    fireEvent.change(screen.getByLabelText('Addressed to (optional)'), {
      target: { value: 'Jo' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Download PDF' }))
    expect(downloadServerPdf).toHaveBeenCalledWith(
      '/api/ExecClaudeConnectorCustomerPdf',
      { tenantFilter: 'contoso.com', ContactName: 'Jo', PreparedBy: '' },
      'Claude_for_Microsoft_365_Contoso_Ltd.pdf'
    )
  })
})
