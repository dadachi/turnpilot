import { Controller } from "@hotwired/stimulus"

// A transient toast: shown when the copilot adapts (e.g. Override raises the shop's alert
// threshold). Fades itself out and removes after a few seconds so toasts don't pile up.
export default class extends Controller {
  connect() {
    this.timeout = setTimeout(() => {
      this.element.style.transition = "opacity .3s"
      this.element.style.opacity = "0"
      this.removal = setTimeout(() => this.element.remove(), 300)
    }, 5000)
  }

  disconnect() {
    clearTimeout(this.timeout)
    clearTimeout(this.removal)
  }
}
