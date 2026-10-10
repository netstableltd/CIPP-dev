import React from 'react'
import { describe, it, expect, vi, beforeEach } from 'vitest'
import { screen, fireEvent } from '@testing-library/react'
import { renderWithProviders } from '../../test-utils'
import { CippDeviceRulesTable } from '../../../src/components/CippReports/CippDeviceRulesTable'
import { ApiGetCall, ApiPostCall } from '../../../src/api/ApiCall'

vi.mock('../../../src/api/ApiCall', () => ({
  ApiGetCall: vi.fn(),
  ApiPostCall: vi.fn(),
}))
vi.mock('../../../src/components/CippComponents/CippApiResults', () => ({
  CippApiResults: () => null,
}))

const RULES = {
  Rules: [
    {
      id: 'intelGeneration',
      group: 'Hardware',
      kind: 'below',
      label: 'Intel Core processor generation',
      unit: 'generation',
      check: 9,
      attention: 8,
      isDefault: true,
      default: { check: 9, attention: 8 },
    },
    {
      id: 'memoryGB',
      group: 'Hardware',
      kind: 'below',
      label: 'Memory fitted',
      unit: 'GB',
      check: 16,
      attention: 8,
      isDefault: false,
      default: { check: 8, attention: 8 },
    },
    {
      id: 'windowsHome',
      group: 'Windows',
      kind: 'flag',
      label: 'Windows Home edition',
      severity: 'check',
      isDefault: true,
      default: { severity: 'check' },
    },
    {
      id: 'driveFull',
      group: 'Health',
      kind: 'above',
      label: 'Drive used',
      unit: '%',
      check: 75,
      attention: null,
      isDefault: true,
      default: { check: 75, attention: null },
    },
    {
      id: 'memoryThreshold',
      group: 'Health',
      kind: 'setting',
      label: 'High memory threshold',
      unit: '%',
      value: 90,
      isDefault: true,
      default: { value: 90 },
    },
  ],
  LastModifiedBy: 'dave@contoso.com',
}

let mutate
beforeEach(() => {
  mutate = vi.fn()
  const result = {
    isSuccess: true,
    isFetching: false,
    isError: false,
    data: RULES,
    dataUpdatedAt: 1,
  }
  ApiGetCall.mockImplementation(() => result)
  ApiPostCall.mockImplementation(() => ({ mutate, isPending: false }))
})

describe('CippDeviceRulesTable', () => {
  it('shows each rule under its group, with blank thresholds as never and changed rules marked', () => {
    renderWithProviders(<CippDeviceRulesTable />)
    expect(screen.getByText('Hardware')).toBeInTheDocument()
    expect(screen.getByText('Windows')).toBeInTheDocument()
    expect(
      screen.getByLabelText('Intel Core processor generation check')
    ).toHaveValue(9)
    expect(screen.getByLabelText('Drive used needs attention')).toHaveValue(
      null
    )
    expect(screen.getAllByText('changed')).toHaveLength(1)
    expect(screen.getByText('8 / 8')).toBeInTheDocument()
  })

  it('saves every rule, with an emptied box as null', () => {
    renderWithProviders(<CippDeviceRulesTable />)
    const save = screen.getByRole('button', { name: 'Save rules' })
    expect(save).toBeDisabled()
    fireEvent.change(screen.getByLabelText('Drive used check'), {
      target: { value: '80' },
    })
    fireEvent.change(
      screen.getByLabelText('Intel Core processor generation check'),
      { target: { value: '' } }
    )
    fireEvent.click(save)
    expect(mutate).toHaveBeenCalledTimes(1)
    const { url, data } = mutate.mock.calls[0][0]
    expect(url).toBe('/api/ExecReportDeviceRules')
    expect(data.Rules).toEqual([
      { id: 'intelGeneration', check: null, attention: 8 },
      { id: 'memoryGB', check: 16, attention: 8 },
      { id: 'windowsHome', severity: 'check' },
      { id: 'driveFull', check: 80, attention: null },
      { id: 'memoryThreshold', value: 90 },
    ])
  })

  it('resets to the defaults', () => {
    renderWithProviders(<CippDeviceRulesTable />)
    fireEvent.click(screen.getByRole('button', { name: 'Reset to defaults' }))
    expect(mutate).toHaveBeenCalledWith({
      url: '/api/ExecReportDeviceRules',
      data: { Action: 'Reset' },
    })
  })
})
