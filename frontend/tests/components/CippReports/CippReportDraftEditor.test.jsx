import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import {
  CippReportDraftEditor,
  overridesToState,
  stateToOverrides,
} from '../../../src/components/CippReports/CippReportDraftEditor'
import { ApiGetCall, ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))
vi.mock('../../../src/components/CippComponents/CippApiResults', () => ({
  CippApiResults: () => null,
}))
vi.mock('../../../src/components/CippPdf/useServerPdf', () => ({
  useServerPdf: () => ({ pdfUrl: '', loading: false, error: null }),
  ServerPdfPane: () => <div data-testid="pdf" />,
}))

const FINDINGS = [
  {
    Id: 'devices-storage',
    Severity: 'Fix',
    Title: 'Drives over 75% full',
    Detail: 'internal',
    Customer: 'Free up space.',
    CustomerItems: ['SERVER (D: 100% full)'],
  },
  {
    Id: 'devices-home-edition',
    Severity: 'Info',
    Title: 'Windows Home',
    Detail: 'x',
    Customer: 'Upgrade to Pro.',
    CustomerItems: ['CAD1'],
  },
  {
    Id: 'monitoring-silent',
    Severity: 'Fix',
    Title: 'No alerts in 90 days',
    Detail: 'check profile',
    Customer: '',
    CustomerItems: [],
  },
]
const DRAFT = {
  Id: 't1_2026-09',
  TenantId: 't1',
  Company: 'Contoso Ltd',
  PeriodKey: '2026-09',
  PeriodLabel: 'September 2026',
  Status: 'Draft',
  ReportGUID: 'g1',
  GeneratedAt: '2026-10-10T10:00:00Z',
  GeneratedBy: 'dave',
  Findings: FINDINGS,
  Sections: ['summary', 'breaches'],
  Overrides: { Note: 'Hello', HiddenFindings: ['devices-home-edition'] },
}

let mutate
beforeEach(() => {
  mutate = vi.fn()
  const results = {
    draft: { isSuccess: true, isError: false, data: DRAFT, dataUpdatedAt: 1 },
    catalog: {
      isSuccess: true,
      data: [
        { value: 'summary', label: 'Summary' },
        { value: 'breaches', label: 'Data Breaches' },
      ],
    },
  }
  ApiGetCall.mockImplementation(({ url }) =>
    url.includes('ListReportDrafts') ? results.draft : results.catalog
  )
  ApiPostCall.mockImplementation(() => ({ mutate, isPending: false }))
})

describe('draft overrides', () => {
  it('only keeps wording that differs from the original', () => {
    const s = overridesToState({})
    s.text = {
      'devices-storage': 'Free up space.',
      'devices-home-edition': 'Move to Pro soon.',
    }
    s.items = { 'devices-storage': 'SERVER (D: 100% full)' }
    const o = stateToOverrides(s, FINDINGS)
    expect(o.FindingText).toEqual({
      'devices-home-edition': 'Move to Pro soon.',
    })
    expect(o.FindingItems).toEqual({})
  })
})

describe('CippReportDraftEditor', () => {
  it('shows the saved changes, and keeps internal items out of the recommendations', () => {
    renderWithProviders(<CippReportDraftEditor id="t1_2026-09" />)
    expect(screen.getByLabelText('Note from your IT team')).toHaveValue('Hello')
    expect(screen.getByLabelText('Include Drives over 75% full')).toBeChecked()
    expect(screen.getByLabelText('Include Windows Home')).not.toBeChecked()
    expect(screen.queryByLabelText('Include No alerts in 90 days')).toBeNull()
    expect(
      screen.getByText('Pre-check items (not shown to the customer)')
    ).toBeInTheDocument()
    expect(screen.getByText('Data Breaches')).toBeInTheDocument()
  })

  it('saves the changes and regenerates, and approval waits for the save', () => {
    renderWithProviders(<CippReportDraftEditor id="t1_2026-09" />)
    fireEvent.click(screen.getByLabelText('Include Windows Home'))
    expect(screen.getByRole('button', { name: 'Approve' })).toBeDisabled()
    fireEvent.click(screen.getByRole('button', { name: 'Save and update PDF' }))
    const { data } = mutate.mock.calls[0][0]
    expect(data.Action).toBe('Generate')
    expect(data.Period).toBe('2026-09')
    expect(data.Overrides.Note).toBe('Hello')
    expect(data.Overrides.HiddenFindings).toEqual([])
  })
})
