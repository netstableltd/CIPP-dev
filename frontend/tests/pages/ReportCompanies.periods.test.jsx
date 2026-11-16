import React from 'react'
import { screen, waitFor } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { LocalizationProvider } from '@mui/x-date-pickers/LocalizationProvider'
import { AdapterDateFns } from '@mui/x-date-pickers/AdapterDateFns'
import { renderWithProviders } from '../test-utils'
import { api, getResult, postResult } from '../mocks/api-call'
import { CippApiDialog } from '../../src/components/CippComponents/CippApiDialog'
import {
  reportCoverOptions,
  reportRunPeriodOptions,
} from '../../src/utils/report-periods'

// Reports > Companies: a draft or test can cover any period (the company's usual one, the last
// 30 days, custom dates), and each company can say what its report covers (mid-month reports).
const tableProps = vi.hoisted(() => ({ current: null }))
vi.mock('../../src/api/ApiCall', async () =>
  (await import('../mocks/api-call')).apiCallMock()
)
vi.mock('../../src/components/CippComponents/CippTablePage.jsx', () => ({
  CippTablePage: (props) => {
    tableProps.current = props
    return <div data-testid="table-page-stub" />
  },
}))

import Page from '../../src/pages/reports/companies/index.jsx'

const company = {
  TenantId: '11111111-1111-1111-1111-111111111111',
  displayName: 'Contoso Ltd',
  ReportPeriod: 'Default',
}
const emptyGet = getResult()

const getAction = (label) => {
  api.get = () => emptyGet
  const { unmount } = renderWithProviders(<Page />)
  const action = tableProps.current.actions.find((a) => a.label === label)
  unmount()
  return action
}

describe('Report periods', () => {
  it('offers the same period values the backend accepts', () => {
    expect(reportRunPeriodOptions.map((o) => o.value)).toEqual([
      'Scheduled',
      'LastMonth',
      'RollingMonth',
      'Last7Days',
      'Last30Days',
      'Last90Days',
      'ThisMonth',
      'Custom',
    ])
    expect(reportCoverOptions.map((o) => o.value)).toEqual([
      'LastMonth',
      'RollingMonth',
      'Last30Days',
    ])
  })

  it('lets the draft and test actions pick a period and custom dates', () => {
    for (const label of [
      'Create draft for review',
      'Test customer report',
      'Test pre-check',
    ]) {
      const names = getAction(label).fields.map((f) => f.name)
      expect(names).toEqual(
        expect.arrayContaining(['Period', 'StartDate', 'EndDate'])
      )
    }
  })

  it('shows the dates only for custom dates, and posts the period chosen', async () => {
    const post = postResult()
    api.post = () => post
    const action = getAction('Create draft for review')
    const user = userEvent.setup()
    renderWithProviders(
      <LocalizationProvider dateAdapter={AdapterDateFns}>
        <CippApiDialog
          createDialog={{ open: true, handleClose: vi.fn() }}
          title="Create draft for review"
          fields={action.fields}
          api={action}
          row={company}
        />
      </LocalizationProvider>
    )

    expect(screen.queryByLabelText('First day')).not.toBeInTheDocument()
    await user.click(screen.getByRole('combobox', { name: 'Period' }))
    await user.click(
      await screen.findByRole('option', { name: 'Custom dates' })
    )
    expect((await screen.findAllByText('First day')).length).toBeGreaterThan(0)
    expect(screen.getAllByText('Last day (included)').length).toBeGreaterThan(0)

    await user.click(screen.getByRole('combobox', { name: 'Period' }))
    await user.click(
      await screen.findByRole('option', { name: 'Last 30 days' })
    )
    await waitFor(() =>
      expect(screen.queryAllByText('First day')).toHaveLength(0)
    )

    await user.click(screen.getByRole('button', { name: 'Confirm' }))
    await waitFor(() => expect(post.mutate).toHaveBeenCalledTimes(1))
    const sent = post.mutate.mock.calls[0][0]
    expect(sent.url).toBe('/api/ExecReportDraft')
    expect(sent.data).toMatchObject({
      Action: 'Generate',
      TenantId: company.TenantId,
      Period: { value: 'Last30Days' },
    })
  })

  it('lets a company say what its report covers', () => {
    const field = getAction('Edit report settings').fields.find(
      (f) => f.name === 'ReportPeriod'
    )
    expect(field.options.map((o) => o.value)).toEqual([
      'Default',
      'LastMonth',
      'RollingMonth',
      'Last30Days',
    ])
  })
})
