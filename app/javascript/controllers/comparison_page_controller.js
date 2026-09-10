import { Controller } from "@hotwired/stimulus"
import {
  getComparisonIds, setComparisonIds, clearComparison, removeFromComparison, rememberCategory,
  reconcileSelection, orderProductsByIds, buildComparisonRows, rowDiffers
} from "comparison"
import { currentUserId } from "current_session"

// Renders /compare: fetches full product data for the stored ids through
// the existing by_ids endpoint (the selection itself only ever holds ids),
// reconciles it against the 4-item/category-consistency rules, and builds
// the comparison table entirely client-side.
export default class extends Controller {
  static targets = [
    "controls", "diffToggle", "loading", "error", "errorMessage", "reconcileNotice",
    "empty", "singlePrompt", "tableWrapper", "headerRow", "body"
  ]
  static values = { byIdsUrl: String, cartItemsUrl: String, newSessionUrl: String }

  connect() {
    this.onlyDifferences = false
    this.products = []
    this.load()
  }

  retry() {
    this.load()
  }

  async load() {
    this.showLoading()
    const ids = getComparisonIds()

    if (ids.length === 0) {
      this.renderEmpty()
      return
    }

    try {
      const url = new URL(this.byIdsUrlValue, window.location.origin)
      ids.forEach((id) => url.searchParams.append("ids[]", id))

      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`Comparison lookup failed with ${response.status}`)

      const fetchedProducts = await response.json()
      const reconciliation = reconcileSelection(ids, fetchedProducts)

      let keptIds = ids
      if (reconciliation.changed) {
        keptIds = setComparisonIds(reconciliation.keptIds)
        window.dispatchEvent(new CustomEvent("comparison:changed", { detail: { ids: keptIds } }))
      }

      this.products = orderProductsByIds(fetchedProducts, keptIds)
      this.products.forEach((product) => rememberCategory(product.id, product.category))

      this.loadingTarget.hidden = true
      this.errorTarget.hidden = true

      if (reconciliation.changed) {
        this.explainReconciliation(reconciliation)
      } else {
        this.reconcileNoticeTarget.hidden = true
      }

      this.renderProducts()
    } catch (error) {
      this.loadingTarget.hidden = true
      this.errorTarget.hidden = false
      this.errorMessageTarget.textContent = "Couldn't load your comparison right now."
    }
  }

  explainReconciliation({ missingIds, categoryDroppedIds, limitDroppedIds }) {
    const parts = []

    if (missingIds.length > 0) {
      parts.push(`${missingIds.length} ${missingIds.length === 1 ? "product is" : "products are"} no longer available`)
    }
    if (categoryDroppedIds.length > 0) {
      parts.push(`${categoryDroppedIds.length} ${categoryDroppedIds.length === 1 ? "product was" : "products were"} removed for not matching the comparison's category`)
    }
    if (limitDroppedIds.length > 0) {
      parts.push(`${limitDroppedIds.length} ${limitDroppedIds.length === 1 ? "product was" : "products were"} removed to stay within the 4-item limit`)
    }

    if (parts.length === 0) {
      this.reconcileNoticeTarget.hidden = true
      return
    }

    this.reconcileNoticeTarget.textContent = `Your comparison was updated: ${parts.join("; ")}.`
    this.reconcileNoticeTarget.hidden = false
  }

  renderProducts() {
    if (this.products.length === 0) {
      this.renderEmpty()
      return
    }

    this.emptyTarget.hidden = true
    this.controlsTarget.hidden = false
    this.singlePromptTarget.hidden = this.products.length !== 1
    this.renderTable()
  }

  renderTable() {
    this.buildHeader()

    const rows = buildComparisonRows(this.products)
    const visibleRows = this.onlyDifferences ? rows.filter(rowDiffers) : rows

    this.bodyTarget.replaceChildren()

    if (visibleRows.length === 0) {
      this.bodyTarget.appendChild(this.buildNoDifferencesRow())
    } else {
      visibleRows.forEach((row) => this.bodyTarget.appendChild(this.buildRow(row)))
    }

    this.tableWrapperTarget.hidden = false
  }

  toggleDifferencesOnly(event) {
    this.onlyDifferences = event.target.checked
    if (this.products.length > 0) this.renderTable()
  }

  removeProduct(id) {
    const ids = removeFromComparison(id)
    window.dispatchEvent(new CustomEvent("comparison:changed", { detail: { ids } }))
    this.products = this.products.filter((product) => product.id !== id)
    this.reconcileNoticeTarget.hidden = true
    this.renderProducts()
  }

  clearAll() {
    clearComparison()
    window.dispatchEvent(new CustomEvent("comparison:changed", { detail: { ids: [] } }))
    this.products = []
    this.renderEmpty()
  }

  showLoading() {
    this.loadingTarget.hidden = false
    this.errorTarget.hidden = true
    this.reconcileNoticeTarget.hidden = true
    this.emptyTarget.hidden = true
    this.singlePromptTarget.hidden = true
    this.tableWrapperTarget.hidden = true
    this.controlsTarget.hidden = true
  }

  renderEmpty() {
    this.loadingTarget.hidden = true
    this.errorTarget.hidden = true
    this.reconcileNoticeTarget.hidden = true
    this.controlsTarget.hidden = true
    this.singlePromptTarget.hidden = true
    this.tableWrapperTarget.hidden = true
    this.emptyTarget.hidden = false
  }

  buildHeader() {
    this.headerRowTarget.replaceChildren()

    const cornerTh = document.createElement("th")
    cornerTh.scope = "col"
    cornerTh.className = "comparison-table__row-label"
    this.headerRowTarget.appendChild(cornerTh)

    this.products.forEach((product) => {
      this.headerRowTarget.appendChild(this.buildProductHeader(product))
    })
  }

  buildProductHeader(product) {
    const th = document.createElement("th")
    th.scope = "col"
    th.className = "comparison-table__product"

    const link = document.createElement("a")
    link.href = `/products/${product.id}`
    link.className = "comparison-table__link"

    if (product.image_url) {
      const img = document.createElement("img")
      img.src = product.image_url
      img.alt = product.name
      img.className = "comparison-table__image"
      link.appendChild(img)
    }

    const name = document.createElement("span")
    name.className = "comparison-table__name"
    name.textContent = product.name
    link.appendChild(name)

    th.appendChild(link)

    const meta = [ product.brand, product.model ].filter(Boolean).join(" ")
    if (meta) {
      const metaEl = document.createElement("p")
      metaEl.className = "comparison-table__meta"
      metaEl.textContent = meta
      th.appendChild(metaEl)
    }

    if (product.out_of_stock) {
      const status = document.createElement("p")
      status.className = "comparison-table__out-of-stock"
      status.textContent = "Out of stock"
      th.appendChild(status)
    } else {
      th.appendChild(this.buildAddToCartControl(product))
    }

    const removeButton = document.createElement("button")
    removeButton.type = "button"
    removeButton.className = "btn btn--secondary comparison-table__remove"
    removeButton.textContent = "Remove"
    removeButton.setAttribute("aria-label", `Remove ${product.name} from comparison`)
    removeButton.addEventListener("click", () => this.removeProduct(product.id))
    th.appendChild(removeButton)

    return th
  }

  // Reuses the same POST /cart_items flow the product card's button_to
  // renders, respecting the same signed-in/availability rules.
  buildAddToCartControl(product) {
    if (currentUserId() === null) {
      const link = document.createElement("a")
      link.href = this.newSessionUrlValue
      link.className = "btn btn--primary comparison-table__add-to-cart"
      link.textContent = "Sign in to purchase"
      return link
    }

    const form = document.createElement("form")
    form.method = "post"
    form.action = this.cartItemsUrlValue
    form.className = "comparison-table__add-to-cart-form"

    const fields = { authenticity_token: this.csrfToken, product_id: product.id, quantity: 1 }
    Object.entries(fields).forEach(([ name, value ]) => {
      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      form.appendChild(input)
    })

    const submit = document.createElement("button")
    submit.type = "submit"
    submit.className = "btn btn--accent"
    submit.textContent = "Add to Cart"
    form.appendChild(submit)

    return form
  }

  buildRow(row) {
    const tr = document.createElement("tr")
    if (rowDiffers(row)) tr.classList.add("comparison-table__row--differs")

    const th = document.createElement("th")
    th.scope = "row"
    th.className = "comparison-table__row-label"
    th.textContent = row.label
    tr.appendChild(th)

    row.cells.forEach((cell) => {
      const td = document.createElement("td")
      td.textContent = cell.formatted
      tr.appendChild(td)
    })

    return tr
  }

  buildNoDifferencesRow() {
    const tr = document.createElement("tr")
    const td = document.createElement("td")
    td.colSpan = this.products.length + 1
    td.className = "comparison-table__no-differences"
    td.textContent = "All compared products have the same values for the attributes shown."
    tr.appendChild(td)
    return tr
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
