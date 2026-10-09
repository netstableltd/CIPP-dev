import { useState } from 'react'
import { screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { renderWithProviders } from '../../test-utils'
import {
  BLOCK_PRESETS,
  DATE_RANGES,
  PRESET_TOPICS,
  StructuredBlockCard,
  isStructuredBlock,
} from '../../../src/components/ReportBuilder/ReportBuilderBlocks'

vi.mock('../../../src/components/CippPdf/useBrandingSettings', async (importOriginal) => ({
  ...(await importOriginal()),
  useBrandingSettings: () => ({ coverImages: [] }),
}))

const ATERA_TYPES = ['AteraAgents', 'AteraAlerts', 'AteraTickets', 'AteraContracts']
const ateraTopics = PRESET_TOPICS.filter((t) => t.value.startsWith('atera'))
const ateraVariants = ateraTopics.flatMap((t) => t.variants)

// Every collection a block reads: its picked source, or the collections its tokens name.
const collectionsOf = (block) => {
  const source = block.chartSource || block.dataSource || block.statsSource || block.itemsSource
  if (source?.type) return [source.type]
  return (block.stats || []).map((s) => /^&(\w+)/.exec(s.value)?.[1])
}

describe('Atera pre-built blocks', () => {
  it('offers devices, alerts, tickets and contracts', () => {
    expect(ateraTopics.map((t) => t.label)).toEqual([
      'Atera devices',
      'Atera alerts',
      'Atera tickets',
      'Atera contracts',
    ])
  })

  it.each(ateraVariants.map((v) => [v.label, v.preset]))(
    '%s builds a renderable block reading Atera data',
    (_label, preset) => {
      expect(BLOCK_PRESETS[preset]).toBeTypeOf('function')
      const block = BLOCK_PRESETS[preset]()
      expect(isStructuredBlock(block.type)).toBe(true)
      expect(block.static).toBe(true)
      for (const collection of collectionsOf(block)) expect(ATERA_TYPES).toContain(collection)
      const filter = (block.chartSource || block.dataSource)?.filter
      if (filter?.op === 'in') {
        expect(DATE_RANGES.map((r) => r.value)).toContain(filter.value)
      }
    }
  )
})

const dataShape = [
  {
    type: 'AteraTickets',
    count: 9,
    fields: [
      { name: 'TicketCreatedDate', type: 'date' },
      { name: 'TicketStatus', type: 'string' },
    ],
  },
]

const Harness = ({ initial, onChange }) => {
  const [block, setBlock] = useState(initial)
  return (
    <StructuredBlockCard
      block={block}
      index={0}
      totalBlocks={1}
      dataShape={dataShape}
      onRemove={vi.fn()}
      onMoveUp={vi.fn()}
      onMoveDown={vi.fn()}
      onUpdate={(index, next) => {
        onChange(next)
        setBlock(next)
      }}
    />
  )
}

describe('date range condition', () => {
  it('switches the value box to a date range and back', async () => {
    const latest = { current: null }
    renderWithProviders(
      <Harness
        initial={BLOCK_PRESETS.ateraticketstatus()}
        onChange={(next) => {
          latest.current = next
        }}
      />
    )
    // the preset is already filtered to the report period
    expect(screen.getByRole('combobox', { name: 'Date range' })).toHaveValue('The report period')

    await userEvent.click(screen.getByRole('combobox', { name: 'Date range' }))
    await userEvent.click(within(await screen.findByRole('listbox')).getByText('Last 30 days'))
    expect(latest.current.chartSource.filter).toEqual({
      field: 'TicketCreatedDate',
      op: 'in',
      value: 'last-30-days',
    })

    await userEvent.click(screen.getByRole('combobox', { name: 'Condition' }))
    await userEvent.click(within(await screen.findByRole('listbox')).getByText('is'))
    expect(latest.current.chartSource.filter).toEqual({ field: 'TicketCreatedDate', op: '=', value: '' })
    expect(screen.queryByRole('combobox', { name: 'Date range' })).not.toBeInTheDocument()
  })
})
