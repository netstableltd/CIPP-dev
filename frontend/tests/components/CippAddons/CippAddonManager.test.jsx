import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, waitFor, within } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { CippAddonManager } from '../../../src/components/CippAddons/CippAddonManager'
import { ApiGetCall, ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))

const addon = {
  Id: 'claude-m365',
  Name: 'Claude for Microsoft 365',
  Version: '1.3.0',
  Author: 'Netstable',
  Category: 'Standard process',
  Description: 'Sets up Claude.',
  Enabled: true,
  Status: 'Untested',
  StatusMessage: 'Not yet tested on CIPP 11.3.0 (last tested on 11.2.1).',
  MissingFunctions: [],
  MissingEndpoints: [],
  MinVersion: '11.0.0',
  TestedWith: ['11.0.2', '11.2.1'],
  TestedOnLatest: false,
  Menu: [
    {
      title: 'Claude for Microsoft 365',
      path: '/addons/claude-m365',
      placement: 'Community Additions',
      preferredPlacement: 'Tenant Administration > Applications',
    },
  ],
  CoreChanges: [{ area: 'Report PDF renderer (CIPPSharp)' }],
  Storage: [{ table: 'CommunityProcesses' }],
  PackageAvailable: true,
  PackageBytes: 80000,
}
const upload = {
  RowKey: 'demo-addon_1.0.0',
  Id: 'demo-addon',
  Name: 'Demo',
  Version: '1.0.0',
  FileName: 'demo-addon-1.0.0.zip',
  Bytes: 2048,
  Sha256: 'abc123',
  UploadedBy: 'dave',
  UploadedAt: '2026-10-30T10:00:00Z',
  Warnings: ['The package has no tests.'],
  Status: 'Compatible',
  StatusMessage: 'Tested on CIPP 11.3.',
  Installed: 'New',
}

let mutate
const setList = (data) =>
  ApiGetCall.mockReturnValue({
    isLoading: false,
    isError: false,
    isSuccess: true,
    data,
  })
beforeEach(() => {
  vi.clearAllMocks()
  mutate = vi.fn()
  ApiPostCall.mockReturnValue({
    mutate,
    reset: vi.fn(),
    isPending: false,
    isError: false,
    data: undefined,
  })
  setList({
    CippVersion: '11.3.0',
    LatestCippVersion: '11.4.0',
    Addons: [addon],
    Uploads: [upload],
    Limits: { packageBytes: 10485760 },
  })
})

describe('CippAddonManager', () => {
  it('shows this and the newest CIPP version', () => {
    renderWithProviders(<CippAddonManager />)
    expect(screen.getByText(/CIPP 11.4.0 is out/)).toBeInTheDocument()
  })

  it('shows an installed add-on with its compatibility, testing and placement', () => {
    renderWithProviders(<CippAddonManager />)
    const card = within(screen.getByTestId('addon-claude-m365'))
    expect(card.getByText('Claude for Microsoft 365')).toBeInTheDocument()
    expect(card.getByText('Not tested on this version')).toBeInTheDocument()
    expect(card.getByText(/last tested on 11.2.1/)).toBeInTheDocument()
    expect(
      card.getByText('Not tested yet: check it before updating CIPP')
    ).toBeInTheDocument()
    expect(
      card.getByText(/could later move to Tenant Administration > Applications/)
    ).toBeInTheDocument()
    expect(card.getByRole('link', { name: /Open/ })).toHaveAttribute(
      'href',
      '/addons/claude-m365'
    )
  })

  it('lists what is missing for an add-on with a problem', () => {
    setList({
      CippVersion: '11.3.0',
      Addons: [
        { ...addon, Status: 'Problem', MissingFunctions: ['Get-CIPPGone'] },
      ],
      Uploads: [],
    })
    renderWithProviders(<CippAddonManager />)
    expect(screen.getByText('Problem')).toBeInTheDocument()
    expect(screen.getByText(/Get-CIPPGone/)).toBeInTheDocument()
  })

  it('asks before turning an add-on off, then turns it off', async () => {
    renderWithProviders(<CippAddonManager />)
    fireEvent.click(
      screen.getByRole('switch', { name: 'Claude for Microsoft 365 turned on' })
    )
    expect(mutate).not.toHaveBeenCalled()
    fireEvent.click(await screen.findByRole('button', { name: 'Turn off' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecAddon',
      data: { Action: 'Disable', Id: 'claude-m365' },
    })
  })

  it('turns an add-on on without asking', () => {
    setList({
      CippVersion: '11.3.0',
      Addons: [{ ...addon, Enabled: false }],
      Uploads: [],
    })
    renderWithProviders(<CippAddonManager />)
    expect(screen.queryByRole('link', { name: /Open/ })).toBeNull()
    fireEvent.click(
      screen.getByRole('switch', { name: 'Claude for Microsoft 365 turned on' })
    )
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecAddon',
      data: { Action: 'Enable', Id: 'claude-m365' },
    })
  })

  it('shows uploads and removes one', () => {
    renderWithProviders(<CippAddonManager />)
    const card = within(screen.getByTestId('upload-demo-addon_1.0.0'))
    expect(card.getByText('Demo 1.0.0')).toBeInTheDocument()
    expect(card.getByText('New add-on')).toBeInTheDocument()
    expect(card.getByText('The package has no tests.')).toBeInTheDocument()
    fireEvent.click(card.getByRole('button', { name: 'Remove' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecAddon',
      data: { Action: 'DeleteUpload', RowKey: 'demo-addon_1.0.0' },
    })
  })

  it('uploads a zip as a data URL and refuses other files', async () => {
    renderWithProviders(<CippAddonManager />)
    fireEvent.change(screen.getByTestId('addon-file'), {
      target: { files: [new File(['x'], 'notes.txt')] },
    })
    expect(
      await screen.findByText('Choose an add-on package (.zip).')
    ).toBeInTheDocument()
    expect(mutate).not.toHaveBeenCalled()
    fireEvent.change(screen.getByTestId('addon-file'), {
      target: {
        files: [new File(['PK'], 'demo.zip', { type: 'application/zip' })],
      },
    })
    await waitFor(() => expect(mutate).toHaveBeenCalled())
    const call = mutate.mock.calls[0][0]
    expect(call.url).toBe('/api/ExecAddon')
    expect(call.data.Action).toBe('Upload')
    expect(call.data.FileName).toBe('demo.zip')
    expect(call.data.Data).toMatch(/^data:application\/zip;base64,/)
  })

  it('shows why an upload was refused', () => {
    ApiPostCall.mockReturnValue({
      mutate,
      reset: vi.fn(),
      isPending: false,
      isError: true,
      error: {
        response: {
          data: {
            Results: "That package can't be used: 1 problem.",
            Errors: ["'../x.ps1' isn't a plain relative path."],
          },
        },
      },
    })
    renderWithProviders(<CippAddonManager />)
    expect(
      screen.getAllByText(/That package can't be used/).length
    ).toBeGreaterThan(0)
    expect(
      screen.getByText("'../x.ps1' isn't a plain relative path.")
    ).toBeInTheDocument()
  })
})
