import { Controller } from "@hotwired/stimulus"

// Plays a short synthesized chime whenever a new advisory is prepended into this container
// (advisories stream in via Turbo). WebAudio means no asset and it works offline. Audio is
// unlocked by the "Run rush" click, so by demo time the AudioContext is allowed to sound.
export default class extends Controller {
  connect() {
    this.observer = new MutationObserver((mutations) => {
      if (mutations.some((m) => m.addedNodes.length > 0)) this.chime()
    })
    this.observer.observe(this.element, { childList: true })
  }

  disconnect() {
    this.observer?.disconnect()
  }

  chime() {
    try {
      const Ctx = window.AudioContext || window.webkitAudioContext
      if (!Ctx) return
      this.ctx ||= new Ctx()
      const now = this.ctx.currentTime
      const osc = this.ctx.createOscillator()
      const gain = this.ctx.createGain()
      osc.type = "sine"
      osc.frequency.setValueAtTime(880, now)
      osc.frequency.exponentialRampToValueAtTime(1320, now + 0.12)
      gain.gain.setValueAtTime(0.0001, now)
      gain.gain.exponentialRampToValueAtTime(0.18, now + 0.02)
      gain.gain.exponentialRampToValueAtTime(0.0001, now + 0.35)
      osc.connect(gain).connect(this.ctx.destination)
      osc.start(now)
      osc.stop(now + 0.35)
    } catch {
      /* audio unavailable (e.g. no gesture yet) — fail silently */
    }
  }
}
