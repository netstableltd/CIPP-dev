import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, within } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import {
  CippChatGPTAccessStep,
  chatgptAccessDefaults,
  chatgptAccessBody,
} from '../../../src/addons/chatgpt-m365/CippChatGPTAccessStep'
import {
  CippChatGPTCustomerInfo,
  chatgptReadinessItems,
} from '../../../src/addons/chatgpt-m365/CippChatGPTCustomerInfo'
import { chatgptCurrentUsers } from '../../../src/addons/chatgpt-m365/CippChatGPTConnectorProcess'
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

describe('chatgptAccessDefaults', () => {
  it('starts at read only when consent approved everything', () => {
    const d = chatgptAccessDefaults(
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
    const d = chatgptAccessDefaults(
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
    expect(chatgptAccessDefaults(status({})).areas).toEqual({
      mail: true,
      teams: true,
    })
  })
})

describe('chatgptAccessDefaults and self-approvals', () => {
  it('leaves out people who approved ChatGPT themselves, so saving removes them', () => {
    const s = status({
      TenantScopes: ['x'],
      ReadAreas: ['mail'],
      Level: 'read',
      People: [
        { UserId: 'u1', Name: 'Jo', Level: 'drafts' },
        { UserId: 'u9', Name: 'Sam', Level: 'read', SelfApproved: true },
      ],
    })
    const d = chatgptAccessDefaults(s)
    expect(d.people.map((p) => p.user.value)).toEqual(['u1'])
    const body = chatgptAccessBody('contoso.com', d, s)
    expect(body.PeopleLevels).toContainEqual({ User: 'u9', Level: 'read' })
  })
})

describe('chatgptAccessBody', () => {
  it('sends areas, level and people, and removes people taken off the list', () => {
    const body = chatgptAccessBody(
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

describe('chatgptCurrentUsers', () => {
  it('uses group members, else people assigned directly', () => {
    expect(
      chatgptCurrentUsers({
        Group: {
          Exists: true,
          Members: [{ Id: 'u1', Name: 'Jo', Upn: 'jo@c.com' }],
        },
      })
    ).toEqual([{ value: 'u1', label: 'Jo (jo@c.com)' }])
    expect(
      chatgptCurrentUsers({
        Group: { Exists: false },
        Apps: [
          {
            Key: 'ChatGPT',
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

describe('CippChatGPTAccessStep', () => {
  it('warns when everyone has everything, and saves the chosen access', () => {
    renderWithProviders(
      <CippChatGPTAccessStep
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
      screen.getByText(/Everyone can currently send email/)
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
      url: '/api/ExecChatGPTConnector',
      data: {
        tenantFilter: 'contoso.com',
        Action: 'Access',
        ReadAreas: ['mail'],
        TenantLevel: 'drafts',
        PeopleLevels: [{ User: 'u-sam', Level: 'drafts' }],
      },
    })
  })

  it('needs at least one read area, and the app', () => {
    const { unmount } = renderWithProviders(
      <CippChatGPTAccessStep
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
      screen.getByText('Choose at least one thing ChatGPT can read.')
    ).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save access' })).toBeDisabled()
    unmount()
    renderWithProviders(
      <CippChatGPTAccessStep tenant="contoso.com" status={status({})} disabled />
    )
    expect(
      screen.getByRole('button', { name: 'Give consent for this access' })
    ).toBeDisabled()
  })
})

describe('chatgptReadinessItems', () => {
  it('describes what the tenant has', () => {
    const items = chatgptReadinessItems({
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
    expect(chatgptReadinessItems(undefined).every((i) => i.have === null)).toBe(
      true
    )
  })
})

describe('CippChatGPTCustomerInfo', () => {
  it('shows the checks and downloads the PDF with the names', () => {
    renderWithProviders(
      <CippChatGPTCustomerInfo
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
      '/api/ExecChatGPTConnectorCustomerPdf',
      { tenantFilter: 'contoso.com', ContactName: 'Jo', PreparedBy: '' },
      'ChatGPT_for_Microsoft_365_Contoso_Ltd.pdf'
    )
  })
})

describe('Setup summary PDF (shared CippAddonPdfCard)', () => {
  it('downloads the setup summary with the names and group', async () => {
    const { CippAddonPdfCard, addonPdfFileName } =
      await import('../../../src/components/CippAddons/CippAddonPdfCard')
    renderWithProviders(
      <CippAddonPdfCard
        url="/api/ExecChatGPTConnectorSummaryPdf"
        body={{ tenantFilter: 'contoso.com', GroupName: 'SG-ChatGPT-Users' }}
        title="Summary for the customer"
        description="d"
        fileName={addonPdfFileName('ChatGPT_setup_summary', 'Contoso Ltd')}
      />
    )
    fireEvent.change(screen.getByLabelText('From (optional)'), {
      target: { value: 'Dave' },
    })
    fireEvent.click(screen.getByRole('button', { name: 'Download PDF' }))
    expect(downloadServerPdf).toHaveBeenCalledWith(
      '/api/ExecChatGPTConnectorSummaryPdf',
      {
        tenantFilter: 'contoso.com',
        GroupName: 'SG-ChatGPT-Users',
        ContactName: '',
        PreparedBy: 'Dave',
      },
      'ChatGPT_setup_summary_Contoso_Ltd.pdf'
    )
  })
})

describe('CippChatGPTAccessStep without consent', () => {
  it('offers to give consent for exactly the chosen access', () => {
    renderWithProviders(
      <CippChatGPTAccessStep tenant="contoso.com" status={status({})} />
    )
    expect(screen.getByText(/has no admin consent in this tenant yet/)).toBeInTheDocument()
    fireEvent.click(
      screen.getByRole('button', { name: 'Give consent for this access' })
    )
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecChatGPTConnector',
      data: expect.objectContaining({
        Action: 'Access',
        ReadAreas: ['mail', 'teams'],
        TenantLevel: 'read',
      }),
    })
  })
})
