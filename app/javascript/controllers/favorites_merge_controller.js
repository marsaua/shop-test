import { Controller } from "@hotwired/stimulus"
import { getGuestFavoriteIds, clearGuestFavorites } from "guest_favorites"
import { currentUserId } from "current_session"

// Runs once, on any page load while signed in: merges leftover guest
// favorites (added before login) into the account, then clears the guest
// list only after the server confirms the merge. Only rendered for signed-in
// sessions, so it never runs for guests and never touches another account's
// data.
export default class extends Controller {
  static targets = [ "status" ]
  static values = { url: String }

  connect() {
    const ids = getGuestFavoriteIds()
    if (ids.length === 0) return

    this.merge(ids)
  }

  async merge(ids) {
    // Captured before the request goes out: if the user logs out or
    // switches accounts before this resolves, the response belongs to a
    // session no longer on screen - it must not clear this browser's guest
    // list on that session's behalf, nor broadcast its favorites onto
    // whatever page (another account's, or a guest page) is now showing.
    const requestUserId = currentUserId()

    this.setSyncing(true)

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: {
          Accept: "application/json",
          "Content-Type": "application/json",
          "X-CSRF-Token": this.csrfToken
        },
        body: JSON.stringify({ product_ids: ids })
      })

      if (currentUserId() !== requestUserId) return
      if (!response.ok) return

      const data = await response.json()
      if (currentUserId() !== requestUserId) return

      clearGuestFavorites()

      window.dispatchEvent(
        new CustomEvent("favorites:changed", {
          detail: { merged: true, count: data.count, favoritedProductIds: data.favorited_product_ids }
        })
      )
    } catch (error) {
      // Network failure - leave the guest list in place so it's retried on
      // the next signed-in page load instead of silently losing favorites.
    } finally {
      if (currentUserId() === requestUserId) this.setSyncing(false)
    }
  }

  setSyncing(syncing) {
    if (this.hasStatusTarget) this.statusTarget.hidden = !syncing
    window.dispatchEvent(new CustomEvent("favorites:sync-status", { detail: { syncing } }))
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
