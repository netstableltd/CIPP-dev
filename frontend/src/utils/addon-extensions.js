/**
 * Extension points that Community Additions add-ons can plug into, in pages that belong to CIPP itself.
 *
 * An add-on adds to a page by shipping a file with an agreed name in its components folder
 * (src/addons/<id>/). The files are found at build time, so with no add-ons installed (or the add-on
 * removed) the page is exactly as it was. A turned-off add-on's feature flag (Addon.<id>) hides its
 * additions without a rebuild.
 *
 * Extension files are loaded with CIPP itself (and during test setup), so keep them light: import only
 * plain helpers at the top and load components with React.lazy. A component imported at the top would
 * pull its dependencies into every page.
 *
 * userBulkEdit.js(x): extra properties for Identity Management > Users > Edit Properties (the bulk
 * update wizard). Export `userBulkEditProperties`, an array of:
 *   property      unique key (prefix it with the add-on, e.g. 'addonEmailDomain')
 *   label         shown in the property list
 *   singleTenant  true if it only works when every selected user is in one tenant
 *   Input         component({ formControl, name, users, tenant }) for the value, stored at `name`
 *                 (React.lazy is fine: the page renders it inside Suspense)
 *   describe      (value) => text for the confirmation step
 *   isReady       (value) => true once the value is complete enough to submit
 *   request       ({ value, users, tenant }) => { url, data }: sent on its own, not to PatchUser
 */

const loadUserBulkEdit = () => {
  try {
    const context = require.context(
      '../addons',
      true,
      /^\.\/[a-z0-9-]+\/userBulkEdit\.jsx?$/
    )
    return context.keys().flatMap((key) => {
      const addonId = key.split('/')[1]
      const extensionModule = context(key)
      const properties = extensionModule?.userBulkEditProperties ?? []
      return (Array.isArray(properties) ? properties : [])
        .filter(
          (p) =>
            p?.property &&
            p?.label &&
            p?.Input &&
            typeof p?.request === 'function'
        )
        .map((p) => ({ ...p, addonId, isAddonExtension: true }))
    })
  } catch {
    return []
  }
}

export const userBulkEditExtensions = loadUserBulkEdit()

/** Drops the extensions of add-ons whose feature flag is turned off (shown while flags load). */
export const enabledAddonExtensions = (extensions, featureFlags) => {
  if (!Array.isArray(featureFlags)) return extensions
  const off = new Set(
    featureFlags
      .filter(
        (f) =>
          String(f.Id ?? f.id ?? '').startsWith('Addon.') &&
          (f.Enabled === false || f.enabled === false)
      )
      .map((f) => String(f.Id ?? f.id).slice('Addon.'.length))
  )
  return extensions.filter((e) => !off.has(e.addonId))
}
