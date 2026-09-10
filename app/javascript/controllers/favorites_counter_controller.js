import { Controller } from "@hotwired/stimulus"
import { getGuestFavoriteIds } from "guest_favorites"

// Keeps the "Favorites (N)" nav count in sync with heart toggles anywhere
// on the page, without a reload.
export default class extends Controller {
  static targets = [ "count" ]
  static values = { signedIn: Boolean, count: Number }

  connect() {
    if (!this.signedInValue) {
      this.countValue = getGuestFavoriteIds().length
    }
    this.render()

    this.boundOnChanged = this.onChanged.bind(this)
    window.addEventListener("favorites:changed", this.boundOnChanged)
  }

  disconnect() {
    window.removeEventListener("favorites:changed", this.boundOnChanged)
  }

  onChanged(event) {
    const { count } = event.detail

    if (typeof count === "number") {
      this.countValue = count
    } else if (!this.signedInValue) {
      this.countValue = getGuestFavoriteIds().length
    }

    this.render()
  }

  render() {
    this.countTarget.textContent = this.countValue
  }
}
