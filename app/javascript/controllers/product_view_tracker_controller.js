import { Controller } from "@hotwired/stimulus"
import { currentUserId } from "current_session"

// Records a "recently viewed" entry once the product detail page has
// actually rendered for a signed-in user. Only ever instantiated (this
// element is only ever rendered) when a product was found and authorized,
// so a failed/inaccessible product request never reaches here at all -
// and connect() only fires once the element is really in the document,
// never for a Turbo prefetch (which fetches HTML without inserting it).
//
// Tracking is best-effort: any failure here is swallowed rather than
// surfaced, so it can never disrupt browsing the product page.
export default class extends Controller {
  static values = { url: String }

  connect() {
    if (this.recorded) return
    this.recorded = true
    this.record()
  }

  async record() {
    // Captured before the request goes out: if the signed-in identity
    // changes (logout, account switch) before this resolves, the response
    // belongs to a session that's no longer showing on screen and must be
    // ignored, the same way favorite-button guards its own requests.
    const requestUserId = currentUserId()
    if (!requestUserId) return

    try {
      const response = await fetch(this.urlValue, {
        method: "POST",
        headers: { Accept: "application/json", "X-CSRF-Token": this.csrfToken }
      })

      if (currentUserId() !== requestUserId) return
      if (!response.ok) return
    } catch (error) {
      // Network failure, offline, etc. - never disrupt the product page.
    }
  }

  get csrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]')
    return meta ? meta.content : ""
  }
}
