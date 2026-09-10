import { Controller } from "@hotwired/stimulus"

// The track is natively horizontally scrollable (with snap), so it already
// works via touch/trackpad with no JS at all - these prev/next buttons are
// just a convenience layered on top of that.
export default class extends Controller {
  static targets = [ "track" ]

  next() {
    this.scrollByPage(1)
  }

  prev() {
    this.scrollByPage(-1)
  }

  scrollByPage(direction) {
    this.trackTarget.scrollBy({ left: direction * this.trackTarget.clientWidth * 0.9, behavior: "smooth" })
  }
}
