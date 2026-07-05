import { Controller } from "@hotwired/stimulus"

// Opt-in: speak each new advisory aloud so heads-down staff hear it without watching the
// screen. Uses the browser's built-in speechSynthesis — fully offline, no cloud. (The
// REASONING is on-device Gemma; the voice is the browser's local TTS.) Watches the advisory
// list for prepended cards and reads the advisory text.
export default class extends Controller {
  static targets = ["button"]

  connect() {
    this.on = false
    this.list = this.element.querySelector("#advisories")
    if (!this.list || !("speechSynthesis" in window)) return
    this.observer = new MutationObserver((mutations) => {
      if (!this.on) return
      for (const m of mutations) {
        for (const node of m.addedNodes) {
          if (node.nodeType === 1) this.speak(node)
        }
      }
    })
    this.observer.observe(this.list, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
    window.speechSynthesis?.cancel()
  }

  toggle() {
    this.on = !this.on
    if (this.hasButtonTarget) this.buttonTarget.textContent = this.on ? "🔊 Reading aloud" : "Read aloud"
    if (!this.on) window.speechSynthesis?.cancel()
  }

  speak(card) {
    const text = card.querySelector("p.font-semibold")?.textContent?.trim()
    if (!text) return
    const u = new SpeechSynthesisUtterance(text)
    u.rate = 1.05
    window.speechSynthesis.cancel() // don't stack utterances during a burst
    window.speechSynthesis.speak(u)
  }
}
