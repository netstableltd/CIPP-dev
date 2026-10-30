import { describe, expect, it } from 'vitest'
import {
  addonManifests,
  getAddonMenuItems,
  withAddonMenuItems,
} from '../../src/utils/addon-menu'
import { nativeMenuItems } from '../../src/layouts/config'

const menu = [
  {
    title: 'Tenant Administration',
    type: 'header',
    items: [
      {
        title: 'Applications',
        items: [{ title: 'Apps', path: '/apps', permissions: ['x'] }],
      },
    ],
  },
  {
    title: 'Community Additions',
    type: 'header',
    items: [
      {
        title: 'Settings',
        items: [
          {
            title: 'Add-ons',
            path: '/community/settings/addons',
            permissions: ['CIPP.AppSettings.*'],
          },
        ],
      },
    ],
  },
]
const manifest = (placement) => ({
  id: 'demo-addon',
  name: 'Demo',
  menu: [
    {
      title: 'Demo',
      path: '/addons/demo-addon',
      permissions: ['CIPP.Core.*'],
      placement,
    },
  ],
})

describe('add-on menu', () => {
  it('reads the installed add-ons from their manifests', () => {
    expect(addonManifests.map((m) => m.id)).toContain('claude-m365')
  })

  it('puts the installed add-ons under Community Additions, above Settings, in the real menu', () => {
    const community = nativeMenuItems.find(
      (item) => item.title === 'Community Additions'
    )
    const titles = community.items.map((item) => item.title)
    expect(titles).toContain('Claude for Microsoft 365')
    expect(titles.indexOf('Claude for Microsoft 365')).toBeLessThan(
      titles.indexOf('Settings')
    )
    const claude = community.items.find(
      (item) => item.path === '/addons/claude-m365'
    )
    expect(claude.permissions).toEqual(['Tenant.Application.*'])
  })

  it('places an entry in Community Additions by default', () => {
    const result = withAddonMenuItems(menu, [manifest(undefined)])
    expect(result[1].items.map((i) => i.title)).toEqual(['Demo', 'Settings'])
    expect(result[1].items[0]).toEqual({
      title: 'Demo',
      path: '/addons/demo-addon',
      permissions: ['CIPP.Core.*'],
      addonId: 'demo-addon',
    })
  })

  it('honours a placement that exists, keeping the /addons URL', () => {
    const result = withAddonMenuItems(menu, [
      manifest('Tenant Administration > Applications'),
    ])
    expect(result[0].items[0].items.map((i) => i.path)).toEqual([
      '/apps',
      '/addons/demo-addon',
    ])
    expect(result[1].items.map((i) => i.title)).toEqual(['Settings'])
  })

  it('falls back to Community Additions when the placement no longer exists', () => {
    const result = withAddonMenuItems(menu, [
      manifest('Gone Header > Gone Group'),
    ])
    expect(result[1].items[0].path).toBe('/addons/demo-addon')
  })

  it('never changes the menu it is given', () => {
    const before = JSON.stringify(menu)
    withAddonMenuItems(menu, [manifest('Tenant Administration > Applications')])
    expect(JSON.stringify(menu)).toBe(before)
  })

  it('skips entries without a title, path or permissions', () => {
    expect(
      getAddonMenuItems([
        {
          id: 'x',
          menu: [{ title: 'No path', permissions: [] }, { path: '/addons/x' }],
        },
      ])
    ).toEqual([])
  })
})
