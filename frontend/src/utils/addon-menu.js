/**
 * Community Additions add-ons in the menu.
 *
 * Each installed add-on has a manifest at backend/Config/Addons/<id>/addon.json. They are read here at
 * build time (the image build copies them beside the frontend), so an add-on's pages are part of the
 * static menu like any other page: breadcrumbs, search, bookmarks and help links all find them.
 *
 * Turning an add-on off doesn't need a rebuild: its feature flag (Addon.<id>) lists its pages, and a
 * disabled flag's pages are hidden by filterMenuItems like any other flag's.
 *
 * Placement: an entry goes under the header named by its `placement` ("Community Additions", or
 * "<Header> > <Group>" for a group inside a header). If that place doesn't exist (renamed upstream),
 * it falls back to Community Additions. The page's URL is always /addons/<id>/..., wherever it sits, so
 * moving an add-on in the menu never breaks links or bookmarks.
 */

export const COMMUNITY_HEADER_TITLE = 'Community Additions'

const loadAddonManifests = () => {
  try {
    const context = require.context(
      '../../../backend/Config/Addons',
      true,
      /^\.\/[a-z0-9-]+\/addon\.json$/
    )
    return context
      .keys()
      .map((key) => {
        const manifest = context(key)
        return manifest?.default || manifest
      })
      .filter((manifest) => manifest && typeof manifest.id === 'string')
      .sort((a, b) => `${a.name}`.localeCompare(`${b.name}`))
  } catch {
    return []
  }
}

export const addonManifests = loadAddonManifests()

/** Menu entries of the given add-on manifests, each tagged with its add-on id. */
export const getAddonMenuItems = (manifests = addonManifests) =>
  (manifests || []).flatMap((manifest) =>
    (Array.isArray(manifest.menu) ? manifest.menu : [])
      .filter(
        (item) => item?.title && item?.path && Array.isArray(item.permissions)
      )
      .map((item) => ({
        title: item.title,
        path: item.path,
        permissions: item.permissions,
        placement: item.placement || COMMUNITY_HEADER_TITLE,
        addonId: manifest.id,
      }))
  )

const findPlace = (items, placement) => {
  const [headerTitle, groupTitle] = `${placement}`
    .split('>')
    .map((part) => part.trim())
  const header = items.find(
    (item) => item.type === 'header' && item.title === headerTitle
  )
  if (!header) return null
  if (!groupTitle) return header
  return (
    (header.items || []).find(
      (item) => item.title === groupTitle && Array.isArray(item.items)
    ) || null
  )
}

/**
 * Returns the menu with the add-ons' entries added (never mutates it). Entries for Community Additions
 * go before its Settings group. Unknown placements fall back to Community Additions; without that
 * header the menu is returned unchanged.
 */
export const withAddonMenuItems = (items, manifests = addonManifests) => {
  const entries = getAddonMenuItems(manifests)
  if (!Array.isArray(items) || entries.length === 0) return items
  const clone = (list) =>
    list.map((item) =>
      Array.isArray(item.items)
        ? { ...item, items: clone(item.items) }
        : { ...item }
    )
  const menu = clone(items)
  const community = findPlace(menu, COMMUNITY_HEADER_TITLE)
  if (!community) return items

  entries.forEach(({ placement, ...entry }) => {
    const place = findPlace(menu, placement) || community
    place.items = place.items || []
    if (place === community) {
      const settingsIndex = place.items.findIndex(
        (item) => item.title === 'Settings'
      )
      place.items.splice(
        settingsIndex === -1 ? place.items.length : settingsIndex,
        0,
        entry
      )
    } else {
      place.items.push(entry)
    }
  })
  return menu
}
