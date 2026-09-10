// Client-only product comparison. Available to guests and signed-in users
// alike (unlike favorites, there is no server-side record at all) - only
// product IDs are persisted, in a versioned localStorage entry using the
// same shape/invalid-data-drop convention as guest_favorites.js.
//
// This module is deliberately fetch-free and DOM-free so its logic (id
// sanitization, duplicate/limit/category-conflict decisions, restored-
// selection validation, diff detection, formatting) can run under Node's
// built-in test runner (see test/js/comparison.test.mjs) without a browser.
// Anything that needs the network (resolving a product's category when it
// isn't already known) or the DOM lives in the comparison-* Stimulus
// controllers that import this module.
const STORAGE_KEY = "shop_trololo.comparison"
const STORAGE_VERSION = 1

export const MAX_COMPARISON_ITEMS = 4
export const MISSING_VALUE = "—"

function sanitizeIds(ids) {
  const cleaned = (Array.isArray(ids) ? ids : []).map(Number).filter((id) => Number.isInteger(id) && id > 0)
  return Array.from(new Set(cleaned))
}

function readIds() {
  let raw
  try {
    raw = window.localStorage.getItem(STORAGE_KEY)
  } catch (error) {
    return []
  }

  if (!raw) return []

  let parsed
  try {
    parsed = JSON.parse(raw)
  } catch (error) {
    return []
  }

  if (!parsed || typeof parsed !== "object" || parsed.v !== STORAGE_VERSION || !Array.isArray(parsed.ids)) {
    return []
  }

  return sanitizeIds(parsed.ids).slice(0, MAX_COMPARISON_ITEMS)
}

function writeIds(ids) {
  const unique = sanitizeIds(ids).slice(0, MAX_COMPARISON_ITEMS)

  try {
    window.localStorage.setItem(STORAGE_KEY, JSON.stringify({ v: STORAGE_VERSION, ids: unique }))
  } catch (error) {
    // localStorage unavailable (private browsing, quota exceeded, etc.) -
    // the change still applies for this page view, it just won't persist.
  }

  return unique
}

export function getComparisonIds() {
  return readIds()
}

export function isInComparison(productId) {
  return readIds().includes(Number(productId))
}

export function clearComparison() {
  return writeIds([])
}

export function setComparisonIds(ids) {
  return writeIds(ids)
}

export function removeFromComparison(productId) {
  return writeIds(readIds().filter((id) => id !== Number(productId)))
}

// In-memory only (never persisted) map of productId -> category, so the
// category-restriction check can be made without storing anything beyond
// IDs. Populated as compare toggles render on the current page, and as
// product data is fetched (e.g. on the comparison page itself).
const categoryCache = new Map()

export function rememberCategory(productId, category) {
  const id = Number(productId)
  if (Number.isInteger(id) && category) categoryCache.set(id, category)
}

// Returns the selection's category: a string if known (from cache), `null`
// if the selection is empty (no constraint), or `undefined` if the
// selection is non-empty but its category isn't cached yet - callers must
// resolve it (e.g. by fetching the first selected product) before treating
// it as unconstrained.
export function currentSelectionCategory() {
  const ids = readIds()
  if (ids.length === 0) return null

  for (const id of ids) {
    const cached = categoryCache.get(id)
    if (cached) return cached
  }

  return undefined
}

// Pure decision for whether `product` ({ id, category }) can be added to a
// comparison list holding `currentIds`, given `existingCategory` (the
// category already established by the current selection, or null/undefined
// per currentSelectionCategory's contract). Never mutates anything.
export function decideAdd(product, currentIds, existingCategory) {
  const id = Number(product.id)

  if (currentIds.includes(id)) {
    return { status: "duplicate" }
  }

  if (existingCategory && product.category && existingCategory !== product.category) {
    return { status: "category_conflict", existingCategory }
  }

  if (currentIds.length >= MAX_COMPARISON_ITEMS) {
    return { status: "limit_reached" }
  }

  return { status: "ok" }
}

// Applies decideAdd against the real persisted selection and, if allowed,
// persists the addition. `existingCategory` must already be resolved by the
// caller (see currentSelectionCategory's contract above).
export function addLocally(product, existingCategory) {
  const ids = readIds()
  const decision = decideAdd(product, ids, existingCategory)

  if (decision.status !== "ok") {
    return { ...decision, ids }
  }

  rememberCategory(product.id, product.category)
  const nextIds = writeIds([ ...ids, Number(product.id) ])
  return { status: "added", ids: nextIds }
}

export function clearAndAdd(product) {
  writeIds([])
  rememberCategory(product.id, product.category)
  const nextIds = writeIds([ Number(product.id) ])
  return { status: "added", ids: nextIds }
}

// Validates a restored/stored id list against fresh data fetched for it.
// `fetchedProducts` is whatever the API actually returned for those ids
// (a subset of storedIds - anything missing no longer exists or is
// inaccessible). Enforces the same invariants addLocally does (max items,
// single category), using the *first* survivor's category as the
// authoritative one, and reports what changed so the UI can explain it.
export function reconcileSelection(storedIds, fetchedProducts) {
  const fetchedById = new Map(fetchedProducts.map((p) => [ Number(p.id), p ]))
  const missingIds = storedIds.filter((id) => !fetchedById.has(id))

  let baseCategory = null
  const keptIds = []
  const categoryDroppedIds = []
  const limitDroppedIds = []

  for (const id of storedIds) {
    const product = fetchedById.get(id)
    if (!product) continue

    if (keptIds.length >= MAX_COMPARISON_ITEMS) {
      limitDroppedIds.push(id)
      continue
    }

    if (baseCategory === null) {
      baseCategory = product.category
      keptIds.push(id)
      continue
    }

    if (product.category === baseCategory) {
      keptIds.push(id)
    } else {
      categoryDroppedIds.push(id)
    }
  }

  const changed = missingIds.length > 0 || categoryDroppedIds.length > 0 || limitDroppedIds.length > 0

  return { keptIds, missingIds, categoryDroppedIds, limitDroppedIds, changed }
}

export function orderProductsByIds(products, ids) {
  const byId = new Map(products.map((p) => [ Number(p.id), p ]))
  return ids.map((id) => byId.get(id)).filter(Boolean)
}

// Mirrors Product::SPECIFICATION_LABEL_OVERRIDES in app/models/product.rb -
// keep the two lists in sync.
const LABEL_OVERRIDES = {
  ram: "RAM", ssd: "SSD", os: "OS", anc: "ANC", gb: "GB", mah: "mAh", hz: "Hz", w: "W"
}

export function humanizeKey(key) {
  const words = String(key).split("_").filter(Boolean)
  let label = words
    .map((word, index) => (index === 0 ? word.charAt(0).toUpperCase() + word.slice(1).toLowerCase() : word.toLowerCase()))
    .join(" ")

  for (const [ token, replacement ] of Object.entries(LABEL_OVERRIDES)) {
    label = label.replace(new RegExp(`\\b${token}\\b`, "gi"), replacement)
  }

  return label
}

export function formatMoney(cents) {
  return `₴${(cents / 100).toFixed(2)}`
}

// Category enum value -> display label, read from a data attribute the
// layout renders from Product::CATEGORY_LABELS (single source of truth in
// Ruby). Not part of the pure/testable core below since it touches `document`.
let categoryLabelsCache = null

export function categoryLabel(category) {
  if (!categoryLabelsCache) {
    try {
      categoryLabelsCache = JSON.parse(document.body.dataset.categoryLabels || "{}")
    } catch (error) {
      categoryLabelsCache = {}
    }
  }

  return categoryLabelsCache[category] || category
}

export function formatValue(value) {
  if (value === undefined || value === null) return MISSING_VALUE
  if (typeof value === "boolean") return value ? "Yes" : "No"
  if (Array.isArray(value)) return value.length ? value.join(", ") : MISSING_VALUE
  return String(value)
}

function availabilityStatus(product) {
  if (product.out_of_stock) return "out_of_stock"
  if (product.low_stock) return "low_stock"
  return "in_stock"
}

function formatAvailability(status) {
  return { in_stock: "In stock", low_stock: "Low stock", out_of_stock: "Out of stock" }[status] || MISSING_VALUE
}

// Stable, logical order for the fixed attributes; specification rows are
// appended after these, in first-seen order across the selected products
// (the order they were added to the comparison) since specifications have
// no fixed per-category schema to order them against otherwise.
const ATTRIBUTE_ROWS = [
  { key: "brand", label: "Brand", value: (p) => p.brand ?? null, format: formatValue },
  { key: "model", label: "Model", value: (p) => p.model ?? null, format: formatValue },
  { key: "price_cents", label: "Price", value: (p) => p.price_cents, format: formatMoney },
  {
    key: "previous_price_cents",
    label: "Previous price",
    value: (p) => p.previous_price_cents ?? null,
    format: (v) => (v === null ? MISSING_VALUE : formatMoney(v)),
    includeIf: (products) => products.some((p) => p.discounted)
  },
  { key: "availability", label: "Availability", value: (p) => availabilityStatus(p), format: formatAvailability },
  {
    key: "warranty_months",
    label: "Warranty",
    value: (p) => p.warranty_months ?? null,
    format: (v) => (v === null ? MISSING_VALUE : `${v} ${v === 1 ? "month" : "months"}`)
  }
]

// Builds { key, label, cells: [{ raw, formatted }, ...] } rows, one per
// fixed attribute (some conditional) plus one per specification key seen
// across the selection. `products` must already be in selection order.
export function buildComparisonRows(products) {
  const rows = []

  for (const attribute of ATTRIBUTE_ROWS) {
    if (attribute.includeIf && !attribute.includeIf(products)) continue

    rows.push({
      key: attribute.key,
      label: attribute.label,
      cells: products.map((product) => {
        const raw = attribute.value(product)
        return { raw, formatted: attribute.format(raw) }
      })
    })
  }

  const seenSpecKeys = new Set()
  for (const product of products) {
    const specs = product.specifications || {}
    for (const key of Object.keys(specs)) {
      if (seenSpecKeys.has(key)) continue
      seenSpecKeys.add(key)

      rows.push({
        key: `spec:${key}`,
        label: humanizeKey(key),
        cells: products.map((product) => {
          const specs = product.specifications || {}
          const hasKey = Object.prototype.hasOwnProperty.call(specs, key)
          const raw = hasKey ? specs[key] : undefined
          return { raw, formatted: formatValue(raw) }
        })
      })
    }
  }

  return rows
}

// A row "differs" when at least one product's normalized (raw) value isn't
// deep-equal to the first cell's - comparing raw values, never formatted
// strings, and treating "missing" as its own distinct value rather than
// ignoring it.
export function rowDiffers(row) {
  if (row.cells.length < 2) return false
  const first = JSON.stringify(row.cells[0].raw)
  return row.cells.some((cell) => JSON.stringify(cell.raw) !== first)
}
