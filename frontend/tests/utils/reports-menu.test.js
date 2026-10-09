import { describe, it, expect } from 'vitest'
import {
  consolidateReportsMenu,
  isFeatureFlagEnabled,
  REPORTS_MENU_FLAG_ID,
} from '../../src/utils/reports-menu'
import { filterMenuItems } from '../../src/utils/filter-menu-items'
import { nativeMenuItems } from '../../src/layouts/config'

const pagePaths = (items, trail = []) =>
  items.flatMap((item) =>
    item.items
      ? pagePaths(item.items, [...trail, item.title])
      : [[...trail, item.title].join(' > ')]
  )

const leafPaths = (items) =>
  items.flatMap((item) => (item.items ? leafPaths(item.items) : [item.path]))

const menu = [
  {
    title: 'Identity Management',
    type: 'header',
    items: [
      {
        title: 'Administration',
        items: [
          {
            title: 'Users',
            path: '/identity/administration/users',
            permissions: ['Identity.User.*'],
          },
        ],
      },
      {
        title: 'Reports',
        items: [
          {
            title: 'MFA Report',
            path: '/identity/reports/mfa-report',
            permissions: ['Identity.User.*'],
          },
        ],
      },
    ],
  },
  {
    title: 'Reports',
    type: 'header',
    items: [
      {
        title: 'Settings',
        path: '/reports/settings',
        permissions: ['CIPP.Reports.*'],
      },
    ],
  },
  {
    title: 'Tools',
    type: 'header',
    items: [
      {
        title: 'Report Builder',
        path: '/tools/report-builder/generated',
        permissions: ['CIPP.ReportBuilder.*'],
      },
      {
        title: 'Scheduler',
        path: '/cipp/scheduler',
        permissions: ['CIPP.Scheduler.*'],
      },
    ],
  },
]

describe('consolidateReportsMenu', () => {
  it('moves area Reports groups and Report Builder under the Reports header, Settings last', () => {
    expect(pagePaths(consolidateReportsMenu(menu))).toEqual([
      'Identity Management > Administration > Users',
      'Reports > Designer > Report Builder',
      'Reports > Identity Reports > MFA Report',
      'Reports > Settings',
      'Tools > Scheduler',
    ])
  })

  it('does not mutate the input', () => {
    const before = JSON.stringify(menu)
    consolidateReportsMenu(menu)
    expect(JSON.stringify(menu)).toBe(before)
  })

  it('returns the input unchanged when there is no Reports header', () => {
    const noReports = menu.filter((h) => h.title !== 'Reports')
    expect(consolidateReportsMenu(noReports)).toBe(noReports)
  })

  it('keeps every page from the real menu exactly once (nothing lost or duplicated)', () => {
    const before = leafPaths(nativeMenuItems).sort()
    const after = leafPaths(consolidateReportsMenu(nativeMenuItems)).sort()
    expect(after).toEqual(before)
  })

  it('leaves no area Reports groups behind in the real menu', () => {
    const result = consolidateReportsMenu(nativeMenuItems)
    const leftover = result
      .filter((h) => h.title !== 'Reports')
      .flatMap((h) => (h.items || []).filter((i) => i.title === 'Reports'))
    expect(leftover).toEqual([])
  })

  it('still respects permissions after consolidation', () => {
    const filtered = filterMenuItems(consolidateReportsMenu(menu), {
      permissions: ['Identity.User.Read', 'CIPP.Scheduler.Read'],
    })
    expect(pagePaths(filtered)).toEqual([
      'Identity Management > Administration > Users',
      'Reports > Identity Reports > MFA Report',
      'Tools > Scheduler',
    ])
  })
})

describe('isFeatureFlagEnabled', () => {
  it('reads Id/Enabled in either case', () => {
    expect(
      isFeatureFlagEnabled(
        [{ Id: REPORTS_MENU_FLAG_ID, Enabled: true }],
        REPORTS_MENU_FLAG_ID
      )
    ).toBe(true)
    expect(
      isFeatureFlagEnabled(
        [{ id: REPORTS_MENU_FLAG_ID, enabled: true }],
        REPORTS_MENU_FLAG_ID
      )
    ).toBe(true)
    expect(
      isFeatureFlagEnabled(
        [{ Id: REPORTS_MENU_FLAG_ID, Enabled: false }],
        REPORTS_MENU_FLAG_ID
      )
    ).toBe(false)
    expect(isFeatureFlagEnabled(undefined, REPORTS_MENU_FLAG_ID)).toBe(false)
    expect(isFeatureFlagEnabled([], REPORTS_MENU_FLAG_ID)).toBe(false)
  })
})
