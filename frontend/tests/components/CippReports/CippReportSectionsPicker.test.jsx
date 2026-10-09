import React from 'react'
import { describe, it, expect, vi } from 'vitest'
import { screen, fireEvent, within } from '@testing-library/react'
import { useForm, useWatch } from 'react-hook-form'
import { renderWithProviders } from '../../test-utils'
import { CippReportSectionsPicker } from '../../../src/components/CippReports/CippReportSectionsPicker'

const CATALOG = [
  {
    value: 'summary',
    label: 'Summary',
    source: 'Built-in',
    description: 'Headline figures',
  },
  { value: 'devices', label: 'Devices (Atera)', source: 'Built-in' },
  { value: 'support', label: 'Support requests (Atera)', source: 'Built-in' },
  {
    value: 'template:abc',
    label: 'Board pack (Report Builder)',
    source: 'Report Builder',
  },
]
vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(() => ({
    data: CATALOG,
    isFetching: false,
    isSuccess: true,
  })),
}))

function Harness({ initial }) {
  const formControl = useForm({ defaultValues: { Sections: initial } })
  const value = useWatch({ control: formControl.control, name: 'Sections' })
  return (
    <>
      <output data-testid="order">
        {(value || []).map((s) => s.value).join(',')}
      </output>
      <CippReportSectionsPicker
        formControl={formControl}
        name="Sections"
        label="Sections"
        emptyText="Using defaults"
      />
    </>
  )
}

const order = () => {
  const text = screen.getByTestId('order').textContent
  return text ? text.split(',') : []
}
const rows = () => within(screen.getByRole('list')).getAllByRole('listitem')

describe('CippReportSectionsPicker', () => {
  it('lists the chosen sections in order with catalog labels', () => {
    renderWithProviders(
      <Harness
        initial={[
          { label: 'devices', value: 'devices' },
          { label: 'summary', value: 'summary' },
        ]}
      />
    )
    expect(rows().map((r) => r.textContent)).toEqual([
      expect.stringContaining('Devices (Atera)'),
      expect.stringContaining('Summary'),
    ])
  })

  it('reorders with the move buttons', () => {
    renderWithProviders(
      <Harness
        initial={[
          { label: 's', value: 'summary' },
          { label: 'd', value: 'devices' },
        ]}
      />
    )
    fireEvent.click(screen.getByLabelText('Move Summary down'))
    expect(order()).toEqual(['devices', 'summary'])
    fireEvent.click(screen.getByLabelText('Move Summary up'))
    expect(order()).toEqual(['summary', 'devices'])
  })

  it('reorders by dragging a row onto another', () => {
    renderWithProviders(
      <Harness
        initial={[
          { label: 's', value: 'summary' },
          { label: 'd', value: 'devices' },
          { label: 't', value: 'support' },
        ]}
      />
    )
    const dataTransfer = { setData: vi.fn(), effectAllowed: '', dropEffect: '' }
    const [first, , third] = rows()
    fireEvent.dragStart(third, { dataTransfer })
    fireEvent.dragOver(first, { dataTransfer })
    fireEvent.drop(first, { dataTransfer })
    expect(order()).toEqual(['support', 'summary', 'devices'])
  })

  it('removes a section and shows the empty text', () => {
    renderWithProviders(
      <Harness initial={[{ label: 's', value: 'summary' }]} />
    )
    fireEvent.click(screen.getByLabelText('Remove Summary'))
    expect(order()).toEqual([])
    expect(screen.getByText('Using defaults')).toBeTruthy()
  })

  it('adds a section from the catalog, including Report Builder templates', () => {
    renderWithProviders(
      <Harness initial={[{ label: 's', value: 'summary' }]} />
    )
    const input = screen.getByLabelText('Add a section')
    fireEvent.mouseDown(input)
    fireEvent.change(input, { target: { value: 'Board' } })
    fireEvent.click(screen.getByText('Board pack (Report Builder)'))
    expect(order()).toEqual(['summary', 'template:abc'])
  })

  it('flags a deleted template as missing', () => {
    renderWithProviders(
      <Harness
        initial={[{ label: 'template:gone (missing)', value: 'template:gone' }]}
      />
    )
    expect(screen.getByText('template:gone (missing)')).toBeTruthy()
  })
})
