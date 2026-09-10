import { Controller } from "@hotwired/stimulus"
import { clearAndAdd, categoryLabel } from "comparison"

// Global banner (one instance, in the layout) for messages a comparison
// toggle can't resolve on its own: a category conflict (with an explicit,
// user-triggered "clear and start over" action - the selection is never
// cleared automatically), the 4-item limit, or a lookup error.
export default class extends Controller {
  static targets = [ "message", "action" ]

  connect() {
    this.boundOnConflict = this.onConflict.bind(this)
    this.boundOnLimit = this.onLimit.bind(this)
    this.boundOnError = this.onError.bind(this)
    window.addEventListener("comparison:category-conflict", this.boundOnConflict)
    window.addEventListener("comparison:limit-reached", this.boundOnLimit)
    window.addEventListener("comparison:error", this.boundOnError)
  }

  disconnect() {
    window.removeEventListener("comparison:category-conflict", this.boundOnConflict)
    window.removeEventListener("comparison:limit-reached", this.boundOnLimit)
    window.removeEventListener("comparison:error", this.boundOnError)
    window.clearTimeout(this.autoHideTimeout)
  }

  onConflict(event) {
    const { existingCategory, product } = event.detail
    this.pendingProduct = product
    this.show(
      `Your comparison currently has ${categoryLabel(existingCategory)} products. Clear it to compare ${categoryLabel(product.category)} instead?`,
      { actionLabel: "Clear comparison and add" }
    )
  }

  onLimit() {
    this.pendingProduct = null
    this.show("You can compare up to 4 products at a time. Remove one to add another.", { autoHide: true })
  }

  onError(event) {
    this.pendingProduct = null
    this.show(event.detail?.message || "Something went wrong.", { autoHide: true })
  }

  clearAndAdd() {
    if (!this.pendingProduct) return

    const result = clearAndAdd(this.pendingProduct)
    window.dispatchEvent(new CustomEvent("comparison:changed", { detail: { ids: result.ids } }))
    this.hide()
  }

  dismiss() {
    this.hide()
  }

  show(message, { actionLabel, autoHide = false } = {}) {
    window.clearTimeout(this.autoHideTimeout)
    this.messageTarget.textContent = message
    this.element.hidden = false

    if (actionLabel) {
      this.actionTarget.textContent = actionLabel
      this.actionTarget.hidden = false
    } else {
      this.actionTarget.hidden = true
    }

    if (autoHide) {
      this.autoHideTimeout = window.setTimeout(() => this.hide(), 8000)
    }
  }

  hide() {
    this.element.hidden = true
    this.pendingProduct = null
  }
}
