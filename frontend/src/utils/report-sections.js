/**
 * Helpers for the ordered report sections list (Reports > Settings and Reports > Companies).
 *
 * A section list is an array of { label, value } objects, in report order. Values are built-in
 * section ids ('summary', 'devices', ...) or Report Builder templates ('template:<id>'); the
 * catalog comes from /api/ListReportSections.
 */

/**
 * Returns a copy of `list` with the item at `from` moved to position `to`.
 * Out-of-range or no-op moves return the list unchanged (same reference).
 */
export const moveSection = (list, from, to) => {
  if (!Array.isArray(list)) return []
  if (
    from === to ||
    from < 0 ||
    to < 0 ||
    from >= list.length ||
    to >= list.length
  ) {
    return list
  }
  const next = [...list]
  const [item] = next.splice(from, 1)
  next.splice(to, 0, item)
  return next
}

/** Adds a section at the end unless it is already in the list. */
export const addSection = (list, section) => {
  const current = Array.isArray(list) ? list : []
  if (!section?.value || current.some((s) => s.value === section.value)) {
    return current
  }
  return [...current, { label: section.label, value: section.value }]
}

/** Removes the section at `index`. */
export const removeSection = (list, index) =>
  (Array.isArray(list) ? list : []).filter((_, i) => i !== index)

/**
 * Normalises whatever the form holds (ids, { label, value } objects, or nothing) into
 * { label, value, description, source, missing } using the catalog for labels. A section
 * whose template no longer exists is kept and flagged as missing so it can be removed.
 */
export const describeSections = (list, catalog = []) => {
  const byValue = new Map((catalog || []).map((c) => [c.value, c]))
  return (Array.isArray(list) ? list : [])
    .map((item) => (typeof item === 'string' ? { value: item } : item))
    .filter((item) => item?.value)
    .map((item) => {
      const known = byValue.get(item.value)
      return {
        label:
          known?.label ??
          String(item.label ?? item.value).replace(/ \(missing\)$/, ''),
        value: item.value,
        description: known?.description,
        source:
          known?.source ??
          (String(item.value).startsWith('template:')
            ? 'Report Builder'
            : 'Built-in'),
        missing: !known && catalog.length > 0,
      }
    })
}
