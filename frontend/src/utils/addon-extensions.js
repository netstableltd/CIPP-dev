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

/**
 * userActions.js(x): extra actions in the user actions menu (Identity Management > Users, the user's
 * page and JIT admin). Export `userActions`, an array of CIPP action objects (label, type, url, data,
 * fields, confirmText, multiPost, icon, defaultvalues ...) plus:
 *   permissions   who sees it (default ['Identity.User.ReadWrite'])
 *   after         the label of the CIPP action to place it after (default: at the end)
 */
const loadUserActions = () => {
  try {
    const context = require.context('../addons', true, /^\.\/[a-z0-9-]+\/userActions\.jsx?$/)
    return context.keys().flatMap((key) => {
      const addonId = key.split('/')[1]
      const actions = context(key)?.userActions ?? []
      return (Array.isArray(actions) ? actions : [])
        .filter((a) => a?.label && a?.url)
        .map((a) => ({ ...a, addonId, isAddonExtension: true }))
    })
  } catch {
    return []
  }
}

export const userActionExtensions = loadUserActions()

/**
 * Puts add-on actions into CIPP's own list: each after the action named in `after`, or at the end.
 * `allowed(permissions)` decides who sees each one.
 */
export const withAddonUserActions = (actions, extensions, allowed) => {
  const list = [...actions]
  for (const { permissions, after, addonId, isAddonExtension, ...action } of extensions) {
    const entry = {
      ...action,
      condition: () => allowed(permissions ?? ['Identity.User.ReadWrite']),
    }
    const at = after ? list.findIndex((a) => a?.label === after) : -1
    if (at === -1) list.push(entry)
    else list.splice(at + 1, 0, entry)
  }
  return list
}

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
