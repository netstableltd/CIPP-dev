import React from 'react'
import fs from 'fs'
import path from 'path'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, within } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { CippSharedMailboxProcess } from '../../../src/addons/shared-mailbox/CippSharedMailboxProcess'
import { ApiGetCall, ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))
vi.mock('../../../src/components/CippComponents/CippFormUserSelector', () => ({
  CippFormUserSelector: ({ label }) => <div>{label}</div>,
}))
vi.mock(
  '../../../src/components/CippComponents/CippFormDomainSelector',
  () => ({
    CippFormDomainSelector: ({ label }) => <div>{label}</div>,
  })
)

const Options = JSON.parse(
  fs.readFileSync(
    path.resolve(
      __dirname,
      '../../../../backend/Config/Addons/shared-mailbox/SharedMailboxOptions.json'
    ),
    'utf8'
  )
)

let mutate
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
  ApiGetCall.mockImplementation(({ data }) =>
    data?.Identity
      ? { isLoading: false, isFetching: false, isError: false, data: undefined }
      : {
          isLoading: false,
          isFetching: false,
          isError: false,
          data: {
            Options,
            Mailboxes: [{ DisplayName: 'Info', Address: 'info@contoso.com' }],
            Guide: null,
          },
        }
  )
})

describe('CippSharedMailboxProcess', () => {
  it('asks for a single tenant', () => {
    renderWithProviders(<CippSharedMailboxProcess tenant="AllTenants" />)
    expect(screen.getByText(/Choose a single tenant/)).toBeInTheDocument()
  })

  it('shows the four steps and every question with our recommendation selected', () => {
    renderWithProviders(<CippSharedMailboxProcess tenant="contoso.com" />)
    expect(screen.getByText('1. Ask the customer')).toBeInTheDocument()
    expect(screen.getByText('2. The mailbox')).toBeInTheDocument()
    expect(screen.getByText("3. The customer's choices")).toBeInTheDocument()
    expect(
      screen.getByText("4. Tell the customer it's ready")
    ).toBeInTheDocument()
    for (const q of Options.questions) {
      const group = screen.getByRole('radiogroup', { name: q.title })
      const recommended = q.options.find((o) => o.recommended)
      expect(
        within(group).getByRole('radio', {
          name: new RegExp(recommended.label),
        })
      ).toBeChecked()
    }
    expect(screen.getAllByText('Recommended').length).toBe(
      Options.questions.length
    )
  })

  it('shows the effects of the chosen option and the extra field it needs', () => {
    renderWithProviders(<CippSharedMailboxProcess tenant="contoso.com" />)
    const signature = screen.getByRole('radiogroup', { name: 'Signature' })
    fireEvent.click(
      within(signature).getByRole('radio', { name: /Added automatically/ })
    )
    expect(
      screen.getByText(/goes at the very bottom of an email thread/)
    ).toBeInTheDocument()
    expect(
      screen.getAllByLabelText(/Signature \(HTML allowed\)/)[0]
    ).toBeInTheDocument()
  })

  it('warns that a group means people add the mailbox themselves', () => {
    renderWithProviders(<CippSharedMailboxProcess tenant="contoso.com" />)
    fireEvent.click(
      within(
        screen.getByRole('radiogroup', { name: 'Giving people access' })
      ).getByRole('radio', { name: /Through a group/ })
    )
    expect(
      screen.getByText(/won't appear in Outlook by itself through a group/)
    ).toBeInTheDocument()
    expect(screen.getAllByLabelText('Access group').length).toBeGreaterThan(0)
  })

  it('needs the mailbox details before it can create one', () => {
    renderWithProviders(<CippSharedMailboxProcess tenant="contoso.com" />)
    expect(
      screen.getByRole('button', { name: 'Create the shared mailbox' })
    ).toBeDisabled()
    expect(screen.getByText('Give the mailbox a name.')).toBeInTheDocument()
    expect(
      screen.getByText('Create or choose the mailbox first.')
    ).toBeInTheDocument()
  })
})
