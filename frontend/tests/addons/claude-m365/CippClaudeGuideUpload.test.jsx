import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent, waitFor } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { CippClaudeGuideUpload } from '../../../src/addons/claude-m365/CippClaudeGuideUpload'
import { ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))

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
})

const guide = {
  FileName: 'How-to.docx',
  Title: 'Connecting Claude',
  UploadedAt: '2026-10-29T14:00:00Z',
  UploadedBy: 'dave',
}

describe('CippClaudeGuideUpload', () => {
  it('offers an upload when there is no guide', () => {
    renderWithProviders(
      <CippClaudeGuideUpload
        tenant="contoso.com"
        include
        onIncludeChange={vi.fn()}
      />
    )
    expect(screen.getByText('No guide uploaded yet.')).toBeInTheDocument()
    expect(
      screen.getByRole('button', { name: 'Upload guide (.docx)' })
    ).toBeInTheDocument()
    expect(screen.queryByRole('switch')).toBeNull()
  })

  it('uploads a Word document as a data URL', async () => {
    renderWithProviders(
      <CippClaudeGuideUpload
        tenant="contoso.com"
        include
        onIncludeChange={vi.fn()}
      />
    )
    const file = new File(['PK-docx'], 'Guide.docx', {
      type: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    })
    fireEvent.change(screen.getByTestId('guide-file'), {
      target: { files: [file] },
    })
    await waitFor(() => expect(mutate).toHaveBeenCalled())
    const call = mutate.mock.calls[0][0]
    expect(call.url).toBe('/api/ExecClaudeConnectorGuide')
    expect(call.data.Action).toBe('Upload')
    expect(call.data.FileName).toBe('Guide.docx')
    expect(call.data.Data).toMatch(/^data:.*;base64,/)
  })

  it('refuses other files without uploading', async () => {
    renderWithProviders(
      <CippClaudeGuideUpload
        tenant="contoso.com"
        include
        onIncludeChange={vi.fn()}
      />
    )
    fireEvent.change(screen.getByTestId('guide-file'), {
      target: { files: [new File(['x'], 'guide.pdf')] },
    })
    expect(
      await screen.findByText('Choose a Word document (.docx).')
    ).toBeInTheDocument()
    expect(mutate).not.toHaveBeenCalled()
  })

  it('shows the guide, removes it, and switches it in and out of the summary', () => {
    const onInclude = vi.fn()
    renderWithProviders(
      <CippClaudeGuideUpload
        tenant="contoso.com"
        guide={guide}
        include
        onIncludeChange={onInclude}
      />
    )
    expect(screen.getByText('How-to.docx')).toBeInTheDocument()
    fireEvent.click(
      screen.getByRole('switch', { name: /Add the connection guide/ })
    )
    expect(onInclude).toHaveBeenCalledWith(false)
    fireEvent.click(screen.getByRole('button', { name: 'Remove' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecClaudeConnectorGuide',
      data: { Action: 'Remove' },
    })
  })
})
