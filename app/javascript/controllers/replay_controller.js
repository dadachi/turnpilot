import { Controller } from "@hotwired/stimulus"

// Drives the live replay: each tick advances the sim clock server-side, firing advisories
// that stream in over Turbo. Ticks are CHAINED (schedule the next only after the current
// finishes) rather than fired on a fixed setInterval — a tick makes several Gemma calls and
// can take longer than the interval, and overlapping ticks would race the advisory
// suppression checks and create duplicates.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 4000 } }

  connect() {
    this.stopped = false
    this.scheduleNext()
  }

  disconnect() {
    this.stopped = true
    clearTimeout(this.timer)
  }

  scheduleNext() {
    if (this.stopped) return
    this.timer = setTimeout(() => this.tick(), this.intervalValue)
  }

  async tick() {
    try {
      await fetch(this.urlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": this.csrfToken, "Accept": "text/vnd.turbo-stream.html" },
        credentials: "same-origin"
      })
    } catch {
      /* transient network error — just try again next cycle */
    }
    this.scheduleNext()
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
