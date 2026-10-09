import { describe, it, expect } from 'vitest'
import {
  addSection,
  describeSections,
  moveSection,
  removeSection,
} from '../../src/utils/report-sections'

const s = (value) => ({ label: value, value })
const values = (list) => list.map((i) => i.value)

describe('moveSection', () => {
  const list = [s('summary'), s('devices'), s('support')]
  it('moves an item down and up', () => {
    expect(values(moveSection(list, 0, 2))).toEqual([
      'devices',
      'support',
      'summary',
    ])
    expect(values(moveSection(list, 2, 0))).toEqual([
      'support',
      'summary',
      'devices',
    ])
  })
  it('ignores no-op and out-of-range moves without copying', () => {
    expect(moveSection(list, 1, 1)).toBe(list)
    expect(moveSection(list, -1, 1)).toBe(list)
    expect(moveSection(list, 0, 3)).toBe(list)
  })
  it('does not mutate the input', () => {
    moveSection(list, 0, 2)
    expect(values(list)).toEqual(['summary', 'devices', 'support'])
  })
})

describe('addSection / removeSection', () => {
  it('adds at the end once, and removes by index', () => {
    let list = addSection([], s('summary'))
    list = addSection(list, { label: 'Devices', value: 'devices', extra: 1 })
    list = addSection(list, s('summary'))
    expect(list).toEqual([s('summary'), { label: 'Devices', value: 'devices' }])
    expect(values(removeSection(list, 0))).toEqual(['devices'])
  })
})

describe('describeSections', () => {
  const catalog = [
    {
      value: 'summary',
      label: 'Summary',
      source: 'Built-in',
      description: 'd',
    },
    {
      value: 'template:abc',
      label: 'Board pack (Report Builder)',
      source: 'Report Builder',
    },
  ]
  it('labels ids and objects from the catalog', () => {
    const rows = describeSections(['summary', s('template:abc')], catalog)
    expect(rows.map((r) => r.label)).toEqual([
      'Summary',
      'Board pack (Report Builder)',
    ])
    expect(rows[1].source).toBe('Report Builder')
    expect(rows.every((r) => !r.missing)).toBe(true)
  })
  it('flags deleted templates once the catalog has loaded, without doubling the label', () => {
    const [row] = describeSections(
      [{ label: 'template:gone (missing)', value: 'template:gone' }],
      catalog
    )
    expect(row.missing).toBe(true)
    expect(row.label).toBe('template:gone')
    expect(describeSections(['template:gone'], [])[0].missing).toBe(false)
  })
  it('handles empty or odd input', () => {
    expect(describeSections(undefined, catalog)).toEqual([])
    expect(describeSections([null, {}, ''], catalog)).toEqual([])
  })
})
