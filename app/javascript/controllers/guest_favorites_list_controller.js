import { Controller } from "@hotwired/stimulus"
import { getGuestFavoriteIds, setGuestFavoriteIds } from "guest_favorites"

// Renders the Favorites page for guests: looks up the ids saved in
// localStorage against the server's current product data (never trusting
// cached price/availability), and silently drops ids for products that no
// longer exist.
export default class extends Controller {
  static targets = [ "grid", "empty", "error", "cardTemplate" ]
  static values = { byIdsUrl: String }

  connect() {
    this.load()
  }

  async load() {
    const ids = getGuestFavoriteIds()

    if (ids.length === 0) {
      this.showEmpty()
      return
    }

    try {
      const url = new URL(this.byIdsUrlValue, window.location.origin)
      ids.forEach((id) => url.searchParams.append("ids[]", id))

      const response = await fetch(url, { headers: { Accept: "application/json" } })
      if (!response.ok) throw new Error(`Favorites lookup failed with ${response.status}`)

      const products = await response.json()
      const keptIds = setGuestFavoriteIds(products.map((product) => product.id))

      if (keptIds.length !== ids.length) {
        window.dispatchEvent(
          new CustomEvent("favorites:changed", { detail: { count: keptIds.length } })
        )
      }

      if (products.length === 0) {
        this.showEmpty()
        return
      }

      products.forEach((product) => this.appendCard(product))
      this.gridTarget.hidden = false
      this.emptyTarget.hidden = true
    } catch (error) {
      this.showError()
    }
  }

  showEmpty() {
    this.gridTarget.hidden = true
    this.emptyTarget.hidden = false
  }

  showError() {
    if (this.hasErrorTarget) this.errorTarget.hidden = false
  }

  appendCard(product) {
    const fragment = this.cardTemplateTarget.content.cloneNode(true)
    const card = fragment.querySelector("[data-product-id]")
    card.dataset.productId = product.id

    const image = fragment.querySelector('[data-role="image"]')
    const placeholder = fragment.querySelector('[data-role="placeholder"]')
    if (product.image_url) {
      image.src = product.image_url
      image.alt = product.name
      image.hidden = false
      placeholder.hidden = true
    }

    fragment.querySelectorAll('[data-role="product-link"]').forEach((link) => {
      link.href = `/products/${product.id}`
    })

    fragment.querySelector('[data-role="name"]').textContent = product.name
    fragment.querySelector('[data-role="price"]').textContent = `₴${(product.price_cents / 100).toFixed(2)}`
    fragment.querySelector('[data-role="out-of-stock"]').hidden = product.in_stock

    const favoriteButton = fragment.querySelector('[data-controller="favorite-button"]')
    favoriteButton.setAttribute("data-favorite-button-product-id-value", product.id)
    favoriteButton.setAttribute("data-favorite-button-product-name", product.name)
    favoriteButton.setAttribute("aria-label", `Remove ${product.name} from favorites`)

    this.gridTarget.appendChild(fragment)
  }
}
