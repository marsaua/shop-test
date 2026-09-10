import { Controller } from "@hotwired/stimulus"
import { isGuestFavorite, addGuestFavorite, removeGuestFavorite } from "guest_favorites"
import { currentUserId } from "current_session"

// Heart toggle used on product cards, the product detail page, and the
// Favorites page. Signed-in users are persisted on the server (optimistic,
// with rollback on failure); guests are persisted in localStorage only, so
// nothing here ever caches an authenticated user's favorites client-side.
export default class extends Controller {
  static values = {
    productId: Number,
    favorited: Boolean,
    signedIn: Boolean,
    url: String
  }

  connect() {
    this.pending = false
    this.boundOnExternalChange = this.onExternalChange.bind(this)
    this.boundOnSyncStatus = this.onSyncStatus.bind(this)
    window.addEventListener("favorites:changed", this.boundOnExternalChange)
    window.addEventListener("favorites:sync-status", this.boundOnSyncStatus)

    if (!this.signedInValue) {
      this.favoritedValue = isGuestFavorite(this.productIdValue)
      this.render()
    }
  }

  disconnect() {
    window.removeEventListener("favorites:changed", this.boundOnExternalChange)
    window.removeEventListener("favorites:sync-status", this.boundOnSyncStatus)
  }

  toggle() {
    if (this.pending) return

    if (this.signedInValue) {
      this.toggleRemote()
    } else {
      this.toggleLocal()
    }
  }

  toggleLocal() {
    const nextFavorited = !this.favoritedValue
    const ids = nextFavorited
      ? addGuestFavorite(this.productIdValue)
      : removeGuestFavorite(this.productIdValue)

    this.favoritedValue = nextFavorited
    this.render()
    this.broadcast(nextFavorited, ids.length)
  }

  async toggleRemote() {
    const previousFavorited = this.favoritedValue
    const nextFavorited = !previousFavorited
    // Captured before the request goes out: if the signed-in identity
    // changes (logout, account switch) before this resolves, the response
    // belongs to a session that's no longer showing on screen and must not
    // touch this button or broadcast a stale account's state to the page.
    const requestUserId = currentUserId()

    this.pending = true
    this.element.disabled = true
    this.favoritedValue = nextFavorited
    this.render()

    try {
      const response = await fetch(this.urlValue, {
        method: nextFavorited ? "POST" : "DELETE",
        headers: {
          Accept: "application/json",
          "X-CSRF-Token": this.csrfToken
        }
      })

      if (currentUserId() !== requestUserId) return

      if (!response.ok) throw new Error(`Favorites request failed with ${response.status}`)

      const data = await response.json()
      this.favoritedValue = data.favorited
      this.render()
      this.broadcast(this.favoritedValue, data.count)
    } catch (error) {
      if (currentUserId() !== requestUserId) return

      this.favoritedValue = previousFavorited
      this.render()
      this.reportError("Couldn't update your favorites. Please try again.")
    } finally {
      if (currentUserId() === requestUserId) {
        this.pending = false
        this.element.disabled = false
      }
    }
  }

  onExternalChange(event) {
    const { productId, favorited, merged, favoritedProductIds } = event.detail

    if (merged) {
      if (
        Array.isArray(favoritedProductIds) &&
        favoritedProductIds.includes(this.productIdValue) &&
        !this.favoritedValue
      ) {
        this.favoritedValue = true
        this.render()
      }
      return
    }

    if (Number(productId) === this.productIdValue && favorited !== this.favoritedValue) {
      this.favoritedValue = favorited
      this.render()
    }
  }

  // While the one-time guest->account merge is in flight, disable signed-in
  // heart buttons instead of letting a click interleave with it: the click
  // itself is never lost (the button simply won't accept it until the
  // merge settles), which is simpler and safer here than queuing it behind
  // an in-progress, unrelated bulk write.
  onSyncStatus(event) {
    if (!this.signedInValue || this.pending) return

    this.element.disabled = !!event.detail.syncing
    this.element.setAttribute("aria-busy", event.detail.syncing ? "true" : "false")
  }

  broadcast(favorited, count) {
    window.dispatchEvent(
      new CustomEvent("favorites:changed", {
        detail: { productId: this.productIdValue, favorited, count }
      })
    )
  }

  reportError(message) {
    window.dispatchEvent(new CustomEvent("favorites:error", { detail: { message } }))
  }

  render() {
    this.element.classList.toggle("is-favorited", this.favoritedValue)
    this.element.setAttribute("aria-pressed", this.favoritedValue ? "true" : "false")

    const label = this.element.dataset.favoriteButtonProductName
    if (label) {
      this.element.setAttribute(
        "aria-label",
        this.favoritedValue ? `Remove ${label} from favorites` : `Add ${label} to favorites`
      )
    }
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
