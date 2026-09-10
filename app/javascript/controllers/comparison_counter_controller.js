import { Controller } from "@hotwired/stimulus"
import { getComparisonIds } from "comparison"

// Keeps the "Compare (N)" nav link in sync with comparison toggles anywhere
// on the page, without a reload. Mirrors favorites-counter.
export default class extends Controller {
  static targets = [ "count" ]

  connect() {
    this.render(getComparisonIds().length)
    this.boundOnChanged = this.onChanged.bind(this)
    window.addEventListener("comparison:changed", this.boundOnChanged)
  }

  disconnect() {
    window.removeEventListener("comparison:changed", this.boundOnChanged)
  }

  onChanged(event) {
    const ids = event.detail?.ids || getComparisonIds()
    this.render(ids.length)
  }

  render(count) {
    this.countTarget.textContent = count
  }
}
