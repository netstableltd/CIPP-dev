import React from 'react'
import fs from 'fs'
import path from 'path'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { CippPasswordHandoverSettings } from '../../../src/addons/password-handover/CippPasswordHandoverSettings'
import { ApiGetCall, ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))

const Defaults = JSON.parse(
  fs.readFileSync(
    path.resolve(
      __dirname,
      '../../../../backend/Config/Addons/password-handover/PasswordHandoverDefaults.json'
    ),
    'utf8'
  )
)

let mutate
const load = (server) =>
  ApiGetCall.mockReturnValue({
    isLoading: false,
    isError: false,
    data: { Settings: { ...Defaults, Saved: false }, Server: server },
  })

beforeEach(() => {
  vi.clearAllMocks()
  mutate = vi.fn()
  ApiPostCall.mockReturnValue({ mutate, isPending: false, isError: false, data: undefined })
})

describe('CippPasswordHandoverSettings', () => {
  it('says to set up Password Pusher when there is no server', () => {
    load({ Configured: false })
    renderWithProviders(<CippPasswordHandoverSettings />)
    expect(screen.getByText(/No Password Pusher server is set up yet/)).toBeInTheDocument()
  })

  it('shows the server, the defaults and a preview of the message', () => {
    load({ Configured: true, BaseUrl: 'https://pw.example.com', Authenticated: true })
    renderWithProviders(<CippPasswordHandoverSettings />)
    expect(screen.getByText('https://pw.example.com')).toBeInTheDocument()
    expect(screen.getByLabelText('Lasts (days)')).toHaveValue(14)
    expect(screen.getByLabelText('Can be opened (times)')).toHaveValue(7)
    expect(screen.getByLabelText('Message preview')).toHaveTextContent('opened 7 times')
    expect(screen.getByRole('button', { name: 'Back to the defaults' })).toBeDisabled()
  })

  it('saves the settings, and will not save a message without the link', () => {
    load({ Configured: true, BaseUrl: 'https://pw.example.com' })
    renderWithProviders(<CippPasswordHandoverSettings />)
    fireEvent.change(screen.getByLabelText('Lasts (days)'), { target: { value: '10' } })
    fireEvent.click(screen.getByRole('button', { name: 'Save settings' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecPasswordHandoverSettings',
      data: expect.objectContaining({
        Settings: expect.objectContaining({ expireAfterDays: 10, expireAfterViews: 7 }),
      }),
    })
    fireEvent.change(screen.getByLabelText('Message'), { target: { value: 'No link here' } })
    expect(screen.getByText(/must include \{link\}/)).toBeInTheDocument()
    expect(screen.getByRole('button', { name: 'Save settings' })).toBeDisabled()
  })
})
