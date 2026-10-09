/**
 * Reports menu consolidation.
 *
 * When the `ReportsMenu` feature flag is enabled, CIPP's report pages are gathered under the
 * top-level "Reports" header instead of being spread across each area. Nothing about the pages
 * changes - same paths, same permissions - only where they sit in the sidebar. Permission and
 * feature-flag filtering (filterMenuItems) runs afterwards on the result, exactly as it does on
 * the native menu.
 *
 * Moved:
 *   - every group titled "Reports" directly under an area header (Identity Management, Tenant
 *     Administration, ...) becomes a group under Reports, named after its area
 *     (e.g. "Identity Reports")
 *   - Tools > Report Builder moves into a "Designer" group under Reports
 */

export const REPORTS_MENU_FLAG_ID = 'ReportsMenu'
export const REPORTS_HEADER_TITLE = 'Reports'

// Short group labels for the moved sections; areas not listed fall back to "<Area> Reports".
const AREA_LABELS = {
  'Identity Management': 'Identity Reports',
  'Tenant Administration': 'Tenant Reports',
  'Security & Compliance': 'Security Reports',
  'Copilot & AI': 'Copilot & AI Reports',
  Intune: 'Intune Reports',
  'Teams & SharePoint': 'Teams & SharePoint Reports',
  'Email & Exchange': 'Email Reports',
}

// Pages moved from Tools into the Designer group, by path.
const DESIGNER_PATHS = ['/tools/report-builder/generated']

/**
 * True when the named feature flag is present and enabled in a ListFeatureFlags response.
 * @param {Array} featureFlags
 * @param {string} id
 */
export const isFeatureFlagEnabled = (featureFlags, id) => {
  if (!Array.isArray(featureFlags)) return false
  const flag = featureFlags.find((f) => (f.Id || f.id) === id)
  return Boolean(flag && (flag.Enabled === true || flag.enabled === true))
}

/**
 * Returns a new menu with report pages consolidated under the Reports header.
 * Never mutates the input. If there is no Reports header, the input is returned unchanged.
 *
 * @param {Array} items - native menu items (layouts/config.jsx)
 * @returns {Array}
 */
export const consolidateReportsMenu = (items) => {
  if (!Array.isArray(items)) return items
  const reportsIndex = items.findIndex(
    (item) => item.type === 'header' && item.title === REPORTS_HEADER_TITLE
  )
  if (reportsIndex === -1) return items

  const movedGroups = []
  const designerPages = []

  const reshaped = items.map((header, index) => {
    if (index === reportsIndex || !Array.isArray(header.items)) return header

    const keptItems = []
    for (const child of header.items) {
      const isReportsGroup =
        child.title === 'Reports' && Array.isArray(child.items)
      if (isReportsGroup) {
        movedGroups.push({
          ...child,
          title: AREA_LABELS[header.title] || `${header.title} Reports`,
          movedFrom: header.title,
        })
        continue
      }
      if (child.path && DESIGNER_PATHS.includes(child.path)) {
        designerPages.push({ ...child, movedFrom: header.title })
        continue
      }
      keptItems.push(child)
    }

    if (keptItems.length === header.items.length) return header
    return { ...header, items: keptItems }
  })

  const reportsHeader = reshaped[reportsIndex]
  const ownItems = Array.isArray(reportsHeader.items) ? reportsHeader.items : []

  // Merge moved Designer pages into an existing Designer group, or create one.
  let mergedOwn = ownItems
  if (designerPages.length > 0) {
    const designerIndex = ownItems.findIndex(
      (i) => i.title === 'Designer' && Array.isArray(i.items)
    )
    if (designerIndex === -1) {
      mergedOwn = [...ownItems, { title: 'Designer', items: designerPages }]
    } else {
      mergedOwn = ownItems.map((i, idx) =>
        idx === designerIndex
          ? { ...i, items: [...designerPages, ...i.items] }
          : i
      )
    }
  }

  // Settings stays last: own groups/pages, then moved area groups, then Settings.
  const settingsItems = mergedOwn.filter((i) => i.path === '/reports/settings')
  const otherOwn = mergedOwn.filter((i) => i.path !== '/reports/settings')

  reshaped[reportsIndex] = {
    ...reportsHeader,
    items: [...otherOwn, ...movedGroups, ...settingsItems],
  }
  return reshaped
}
