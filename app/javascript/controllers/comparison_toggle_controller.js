import { Controller } from "@hotwired/stimulus"
import {
  isInComparison, getComparisonIds, currentSelectionCategory, addLocally,
  removeFromComparison, rememberCategory
} from "comparison"

// "Add to comparison" toggle used on product cards and the product detail
// page. Selection lives entirely in localStorage (see comparison.js) - there
// is no signed-in/guest branch here, unlike the favorite button.
export default class extends Controller {
  static values = { productId: Number, category: String, byIdsUrl: String }

  connect() {
    rememberCategory(this.productIdValue, this.categoryValue)
    this.boundOnChanged = this.onChanged.bind(this)
    window.addEventListener("comparison:changed", this.boundOnChanged)
    this.render(isInComparison(this.productIdValue))
  }

  disconnect() {
    window.removeEventListener("comparison:changed", this.boundOnChanged)
  }

  async toggle() {
    if (this.pending) return

    if (isInComparison(this.productIdValue)) {
      const ids = removeFromComparison(this.productIdValue)
      this.render(false)
      this.broadcast(ids)
      return
    }

    this.pending = true
    this.element.setAttribute("aria-busy", "true")

    try {
      const { category: existingCategory, error } = await this.resolveExistingCategory()

      if (error) {
        this.reportError("Couldn't check your current comparison. Please try again.")
        return
      }

      const result = addLocally({ id: this.productIdValue, category: this.categoryValue }, existingCategory)

      switch (result.status) {
        case "added":
          this.render(true)
          this.broadcast(result.ids)
          break
        case "duplicate":
          this.render(true)
          break
        case "category_conflict":
          this.reportConflict(result.existingCategory)
          break
        case "limit_reached":
          this.reportLimitReached()
          break
      }
    } finally {
      this.pending = false
      this.element.setAttribute("aria-busy", "false")
    }
  }

  // The current selection's category only needs to be known when the
  // selection is non-empty; it's resolved from the in-memory cache first
  // (populated by every compare toggle rendered on the page) and, on a
  // cache miss, via one lightweight lookup through the existing by_ids
  // endpoint for the first selected id.
  async resolveExistingCategory() {
    const known = currentSelectionCategory()
    if (known !== undefined) return { category: known }

    const [ firstId ] = getComparisonIds()
    if (!firstId) return { category: null }

    try {
      const url = new URL(this.byIdsUrlValue, window.location.origin)
      url.searchParams.append("ids[]", firstId)

      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`Comparison lookup failed with ${response.status}`)

      const [ product ] = await response.json()
      if (!product) return { category: null }

      rememberCategory(product.id, product.category)
      return { category: product.category }
    } catch (error) {
      return { error: true }
    }
  }

  onChanged(event) {
    const ids = event.detail?.ids || getComparisonIds()
    this.render(ids.includes(this.productIdValue))
  }

  broadcast(ids) {
    window.dispatchEvent(new CustomEvent("comparison:changed", { detail: { ids } }))
  }

  reportConflict(existingCategory) {
    window.dispatchEvent(new CustomEvent("comparison:category-conflict", {
      detail: {
        existingCategory,
        product: { id: this.productIdValue, category: this.categoryValue, name: this.productName }
      }
    }))
  }

  reportLimitReached() {
    window.dispatchEvent(new CustomEvent("comparison:limit-reached"))
  }

  reportError(message) {
    window.dispatchEvent(new CustomEvent("comparison:error", { detail: { message } }))
  }

  render(inComparison) {
    this.element.classList.toggle("is-comparing", inComparison)
    this.element.setAttribute("aria-pressed", inComparison ? "true" : "false")
    this.element.setAttribute(
      "aria-label",
      inComparison ? `Remove ${this.productName} from comparison` : `Add ${this.productName} to comparison`
    )

    const addLabel = this.element.querySelector('[data-role="add-label"]')
    const comparingLabel = this.element.querySelector('[data-role="comparing-label"]')
    if (addLabel) addLabel.hidden = inComparison
    if (comparingLabel) comparingLabel.hidden = !inComparison
  }

  get productName() {
    return this.element.dataset.comparisonToggleProductName
  }
}
