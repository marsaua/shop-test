import { Controller } from "@hotwired/stimulus"

// On the Favorites page: removes a card the moment its heart is unfavorited
// and swaps to the empty state once nothing is left, without a reload.
export default class extends Controller {
  static targets = [ "grid", "empty" ]

  connect() {
    this.boundOnChanged = this.onChanged.bind(this)
    window.addEventListener("favorites:changed", this.boundOnChanged)
  }

  disconnect() {
    window.removeEventListener("favorites:changed", this.boundOnChanged)
  }

  onChanged(event) {
    const { productId, favorited } = event.detail
    if (favorited !== false || productId === undefined) return

    const card = this.gridTarget.querySelector(`[data-product-id="${CSS.escape(String(productId))}"]`)
    if (card) card.remove()

    this.toggleEmptyState()
  }

  toggleEmptyState() {
    const hasCards = this.gridTarget.children.length > 0
    this.gridTarget.hidden = !hasCards
    this.emptyTarget.hidden = hasCards
  }
}
