// Node's built-in test runner (`node --test test/js`) exercises the pure
// logic in app/javascript/comparison.js. No dependency was added for this -
// node:test and node:assert ship with Node itself. This module is
// deliberately fetch-free/DOM-free so it can run here without a browser;
// see comparison.js's header comment for the split rationale. A minimal
// localStorage stub is installed below since comparison.js reads/writes
// window.localStorage and this isn't a browser environment.
import assert from "node:assert/strict"
import { beforeEach, describe, it } from "node:test"

function installLocalStorageStub() {
  const store = new Map()
  globalThis.window = {
    localStorage: {
      getItem: (key) => (store.has(key) ? store.get(key) : null),
      setItem: (key, value) => store.set(key, String(value)),
      removeItem: (key) => store.delete(key)
    }
  }
  return store
}

installLocalStorageStub()

const {
  MAX_COMPARISON_ITEMS,
  getComparisonIds,
  isInComparison,
  clearComparison,
  removeFromComparison,
  rememberCategory,
  currentSelectionCategory,
  decideAdd,
  addLocally,
  clearAndAdd,
  reconcileSelection,
  orderProductsByIds,
  humanizeKey,
  formatMoney,
  formatValue,
  buildComparisonRows,
  rowDiffers
} = await import("../../app/javascript/comparison.js")

beforeEach(() => {
  clearComparison()
})

describe("storage primitives", () => {
  it("starts empty and reflects additions", () => {
    assert.deepEqual(getComparisonIds(), [])
    addLocally({ id: 1, category: "smartphones" }, null)
    assert.deepEqual(getComparisonIds(), [ 1 ])
    assert.equal(isInComparison(1), true)
    assert.equal(isInComparison("1"), true)
    assert.equal(isInComparison(2), false)
  })

  it("removes and clears", () => {
    addLocally({ id: 1, category: "smartphones" }, null)
    addLocally({ id: 2, category: "smartphones" }, "smartphones")
    removeFromComparison(1)
    assert.deepEqual(getComparisonIds(), [ 2 ])
    clearComparison()
    assert.deepEqual(getComparisonIds(), [])
  })

  it("treats corrupted or unversioned localStorage data as empty", () => {
    window.localStorage.setItem("shop_trololo.comparison", "not json")
    assert.deepEqual(getComparisonIds(), [])

    window.localStorage.setItem("shop_trololo.comparison", JSON.stringify([ 1, 2 ]))
    assert.deepEqual(getComparisonIds(), [])

    window.localStorage.setItem("shop_trololo.comparison", JSON.stringify({ v: 999, ids: [ 1 ] }))
    assert.deepEqual(getComparisonIds(), [])
  })

  it("dedupes and drops non-positive-integer ids", () => {
    window.localStorage.setItem(
      "shop_trololo.comparison",
      JSON.stringify({ v: 1, ids: [ 1, 1, 2, -3, 0, "abc", 4.5 ] })
    )
    assert.deepEqual(getComparisonIds(), [ 1, 2 ])
  })
})

describe("decideAdd", () => {
  it("allows adding to an empty or same-category selection under the limit", () => {
    assert.equal(decideAdd({ id: 1, category: "laptops" }, [], null).status, "ok")
    assert.equal(decideAdd({ id: 2, category: "laptops" }, [ 1 ], "laptops").status, "ok")
  })

  it("prevents duplicates", () => {
    const result = decideAdd({ id: 1, category: "laptops" }, [ 1, 2 ], "laptops")
    assert.equal(result.status, "duplicate")
  })

  it("rejects a different category and reports the existing one", () => {
    const result = decideAdd({ id: 3, category: "tvs_and_monitors" }, [ 1 ], "laptops")
    assert.equal(result.status, "category_conflict")
    assert.equal(result.existingCategory, "laptops")
  })

  it("enforces the item limit", () => {
    const result = decideAdd({ id: 5, category: "laptops" }, [ 1, 2, 3, 4 ], "laptops")
    assert.equal(result.status, "limit_reached")
    assert.equal(MAX_COMPARISON_ITEMS, 4)
  })
})

describe("addLocally / currentSelectionCategory / clearAndAdd", () => {
  it("adds and remembers the category for later conflict checks", () => {
    const result = addLocally({ id: 1, category: "headphones" }, null)
    assert.equal(result.status, "added")
    assert.deepEqual(result.ids, [ 1 ])
    assert.equal(currentSelectionCategory(), "headphones")
  })

  it("reports unknown category as undefined when the selection is non-empty but uncached", () => {
    window.localStorage.setItem("shop_trololo.comparison", JSON.stringify({ v: 1, ids: [ 99 ] }))
    assert.equal(currentSelectionCategory(), undefined)
  })

  it("reports null category for an empty selection", () => {
    assert.equal(currentSelectionCategory(), null)
  })

  it("does not mutate storage on a rejected add", () => {
    addLocally({ id: 1, category: "laptops" }, null)
    const before = getComparisonIds()
    const result = addLocally({ id: 2, category: "tvs_and_monitors" }, "laptops")
    assert.equal(result.status, "category_conflict")
    assert.deepEqual(getComparisonIds(), before)
  })

  it("clearAndAdd replaces the whole selection with just the new product", () => {
    addLocally({ id: 1, category: "laptops" }, null)
    addLocally({ id: 2, category: "laptops" }, "laptops")
    const result = clearAndAdd({ id: 9, category: "tvs_and_monitors" })
    assert.equal(result.status, "added")
    assert.deepEqual(getComparisonIds(), [ 9 ])
    assert.equal(currentSelectionCategory(), "tvs_and_monitors")
  })
})

describe("reconcileSelection", () => {
  it("keeps a valid, single-category, in-limit selection untouched", () => {
    const stored = [ 1, 2, 3 ]
    const fetched = stored.map((id) => ({ id, category: "laptops" }))
    const result = reconcileSelection(stored, fetched)
    assert.deepEqual(result, {
      keptIds: [ 1, 2, 3 ], missingIds: [], categoryDroppedIds: [], limitDroppedIds: [], changed: false
    })
  })

  it("drops ids the API no longer returns", () => {
    const result = reconcileSelection([ 1, 2, 3 ], [ { id: 1, category: "laptops" }, { id: 3, category: "laptops" } ])
    assert.deepEqual(result.keptIds, [ 1, 3 ])
    assert.deepEqual(result.missingIds, [ 2 ])
    assert.equal(result.changed, true)
  })

  it("keeps the first item's category and drops later mismatches", () => {
    const fetched = [
      { id: 1, category: "laptops" },
      { id: 2, category: "tvs_and_monitors" },
      { id: 3, category: "laptops" }
    ]
    const result = reconcileSelection([ 1, 2, 3 ], fetched)
    assert.deepEqual(result.keptIds, [ 1, 3 ])
    assert.deepEqual(result.categoryDroppedIds, [ 2 ])
    assert.equal(result.changed, true)
  })

  it("trims to the max item limit, preserving stored order", () => {
    const fetched = [ 1, 2, 3, 4, 5 ].map((id) => ({ id, category: "laptops" }))
    const result = reconcileSelection([ 1, 2, 3, 4, 5 ], fetched)
    assert.deepEqual(result.keptIds, [ 1, 2, 3, 4 ])
    assert.deepEqual(result.limitDroppedIds, [ 5 ])
    assert.equal(result.changed, true)
  })
})

describe("orderProductsByIds", () => {
  it("orders fetched products to match selection order and drops unresolved ids", () => {
    const products = [ { id: 3, name: "C" }, { id: 1, name: "A" }, { id: 2, name: "B" } ]
    assert.deepEqual(
      orderProductsByIds(products, [ 1, 2, 3, 99 ]).map((p) => p.name),
      [ "A", "B", "C" ]
    )
  })
})

describe("humanizeKey", () => {
  it("title-cases the first word and applies known unit overrides", () => {
    assert.equal(humanizeKey("battery_mah"), "Battery mAh")
    assert.equal(humanizeKey("screen_inches"), "Screen inches")
    assert.equal(humanizeKey("ram_gb"), "RAM GB") // "ram" override applies case-insensitively, including the leading word
    assert.equal(humanizeKey("os"), "OS")
    assert.equal(humanizeKey("power_output_w"), "Power output W")
    assert.equal(humanizeKey("active_noise_cancellation"), "Active noise cancellation")
  })
})

describe("formatValue / formatMoney", () => {
  it("renders missing values as an em dash while preserving zero and false", () => {
    assert.equal(formatValue(undefined), "—")
    assert.equal(formatValue(null), "—")
    assert.equal(formatValue(0), "0")
    assert.equal(formatValue(false), "No")
    assert.equal(formatValue(true), "Yes")
    assert.equal(formatValue([]), "—")
    assert.equal(formatValue([ "HDMI x3", "USB x2" ]), "HDMI x3, USB x2")
  })

  it("formats cents as UAH", () => {
    assert.equal(formatMoney(349990), "₴3499.90")
  })
})

describe("buildComparisonRows / rowDiffers", () => {
  const smartphoneA = {
    id: 1, brand: "Voltrix", model: "Nova 12", price_cents: 100000, previous_price_cents: null,
    discounted: false, warranty_months: 12, out_of_stock: false, low_stock: false,
    specifications: { ram_gb: 8, storage_gb: 128, active_noise_cancellation: false }
  }
  const smartphoneB = {
    id: 2, brand: "Nordheim", model: "Pulse S", price_cents: 80000, previous_price_cents: 120000,
    discounted: true, warranty_months: 12, out_of_stock: true, low_stock: false,
    specifications: { ram_gb: 6, screen_inches: 6.4 }
  }

  it("includes the union of specification keys, in first-seen order", () => {
    const rows = buildComparisonRows([ smartphoneA, smartphoneB ])
    const specLabels = rows.filter((r) => r.key.startsWith("spec:")).map((r) => r.label)
    assert.deepEqual(specLabels, [ "RAM GB", "Storage GB", "Active noise cancellation", "Screen inches" ])
  })

  it("only includes a previous-price row when something is discounted", () => {
    const withDiscount = buildComparisonRows([ smartphoneA, smartphoneB ])
    assert.ok(withDiscount.some((r) => r.key === "previous_price_cents"))

    const withoutDiscount = buildComparisonRows([ smartphoneA, { ...smartphoneB, discounted: false } ])
    assert.ok(!withoutDiscount.some((r) => r.key === "previous_price_cents"))
  })

  it("treats a missing spec key as differing from an explicit false/0 value, and formats consistently", () => {
    const rows = buildComparisonRows([ smartphoneA, smartphoneB ])
    const ancRow = rows.find((r) => r.key === "spec:active_noise_cancellation")
    assert.equal(ancRow.cells[0].formatted, "No")
    assert.equal(ancRow.cells[1].formatted, "—")
    assert.equal(rowDiffers(ancRow), true)
  })

  it("does not flag a row as differing when every product shares the same value", () => {
    const rows = buildComparisonRows([ smartphoneA, { ...smartphoneB, warranty_months: 12 } ])
    const warrantyRow = rows.find((r) => r.key === "warranty_months")
    assert.equal(rowDiffers(warrantyRow), false)
  })

  it("flags availability and price as differing based on raw values, not labels", () => {
    const rows = buildComparisonRows([ smartphoneA, smartphoneB ])
    assert.equal(rowDiffers(rows.find((r) => r.key === "availability")), true)
    assert.equal(rowDiffers(rows.find((r) => r.key === "price_cents")), true)
  })

  it("a single product never differs from itself", () => {
    const rows = buildComparisonRows([ smartphoneA ])
    assert.ok(rows.every((row) => rowDiffers(row) === false))
  })
})
