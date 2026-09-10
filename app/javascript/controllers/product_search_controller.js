import { Controller } from "@hotwired/stimulus"

const DEBOUNCE_MS = 300

// Debounces the header/filters search field, submits the filters form as
// a Turbo Frame navigation (the frame's [data-turbo-action="advance"]
// promotes that to a real page visit, so the URL, browser history, and
// shareable/refreshable links all stay in sync for free), and surfaces
// loading/error state around it. Turbo itself aborts a frame's previous
// in-flight fetch when a new navigation targets it, so a fast typist never
// races a stale response into view.
export default class extends Controller {
  static targets = [ "form", "input", "clear", "frame", "status", "error" ]

  connect() {
    this.toggleClear()

    this.onBeforeFetch = this.onBeforeFetch.bind(this)
    this.onFrameLoad = this.onFrameLoad.bind(this)
    this.onFetchError = this.onFetchError.bind(this)
    this.syncFromLocation = this.syncFromLocation.bind(this)

    this.frameTarget.addEventListener("turbo:before-fetch-request", this.onBeforeFetch)
    this.frameTarget.addEventListener("turbo:frame-load", this.onFrameLoad)
    this.frameTarget.addEventListener("turbo:fetch-request-error", this.onFetchError)

    // A search-as-you-type navigation is a frame-promoted "advance": it
    // pushes history and updates the URL without swapping the outer
    // document, so the input (outside the frame) never gets a chance to
    // re-render from a fresh page load. Restoring via back/forward can
    // replay a cached snapshot asynchronously (after popstate has already
    // fired), so resync on turbo:load - the event Turbo guarantees fires
    // once it has finished rendering for a visit, cache or not - rather
    // than trusting whatever the DOM happens to hold at any one instant.
    document.addEventListener("turbo:load", this.syncFromLocation)
    window.addEventListener("popstate", this.syncFromLocation)
  }

  disconnect() {
    this.frameTarget.removeEventListener("turbo:before-fetch-request", this.onBeforeFetch)
    this.frameTarget.removeEventListener("turbo:frame-load", this.onFrameLoad)
    this.frameTarget.removeEventListener("turbo:fetch-request-error", this.onFetchError)
    document.removeEventListener("turbo:load", this.syncFromLocation)
    window.removeEventListener("popstate", this.syncFromLocation)
    window.clearTimeout(this.debounceTimeout)
  }

  syncFromLocation() {
    const value = new URLSearchParams(window.location.search).get("q") || ""
    if (this.inputTarget.value === value) return

    this.inputTarget.value = value
    this.toggleClear()
  }

  onInput() {
    this.toggleClear()
    window.clearTimeout(this.debounceTimeout)
    this.debounceTimeout = window.setTimeout(() => this.submit(), DEBOUNCE_MS)
  }

  clear() {
    window.clearTimeout(this.debounceTimeout)
    this.inputTarget.value = ""
    this.toggleClear()
    this.submit()
    this.inputTarget.focus()
  }

  submit() {
    this.formTarget.requestSubmit()
  }

  toggleClear() {
    this.clearTarget.hidden = this.inputTarget.value.length === 0
  }

  onBeforeFetch() {
    this.errorTarget.hidden = true
    this.statusTarget.textContent = "Searching…"
  }

  onFrameLoad() {
    this.statusTarget.textContent = "Results updated."
  }

  onFetchError() {
    this.statusTarget.textContent = ""
    this.errorTarget.hidden = false
  }
}
