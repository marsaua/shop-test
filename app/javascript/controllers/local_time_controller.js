import { Controller } from "@hotwired/stimulus"

// Reformats a server-rendered UTC timestamp using the viewer's own locale
// and timezone (both read from the browser by Intl). The element's initial
// text is a plain server-rendered fallback so the page is meaningful before
// this runs or if JS is unavailable; this only ever upgrades it in place.
export default class extends Controller {
  static values = { datetime: String, prefix: String }

  connect() {
    const date = new Date(this.datetimeValue)
    if (Number.isNaN(date.getTime())) return

    const formatted = new Intl.DateTimeFormat(undefined, { dateStyle: "medium", timeStyle: "short" }).format(date)
    this.element.textContent = this.prefixValue ? `${this.prefixValue} ${formatted}` : formatted
  }
}
