import { Controller } from "@hotwired/stimulus"

// Polls the tick endpoint on an interval so the seeded rush plays out live: each tick
// advances the simulation clock server-side, firing advisories that stream in over Turbo.
export default class extends Controller {
  static values = { url: String, interval: { type: Number, default: 4000 } }

  connect() {
    this.timer = setInterval(() => this.tick(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
  }

  tick() {
    fetch(this.urlValue, {
      method: "POST",
      headers: { "X-CSRF-Token": this.csrfToken, "Accept": "text/vnd.turbo-stream.html" },
      credentials: "same-origin"
    })
  }

  get csrfToken() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
