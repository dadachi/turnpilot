import { Controller } from "@hotwired/stimulus"

// Opt-in counter camera. On toggle, capture a downscaled JPEG frame every ~5s and POST it
// for on-device Gemma perception. The frame is sent once and never stored — only the derived
// coarse signal is kept server-side. Captures are CHAINED (next only after the current POST
// resolves) so a slow vision call (~1.1s warm, ~7.6s cold) never overlaps.
export default class extends Controller {
  static targets = ["indicator", "button"]
  static values = { url: String, interval: { type: Number, default: 5000 } }

  connect() { this.on = false }
  disconnect() { this.stop() }

  toggle() { this.on ? this.stop() : this.start() }

  async start() {
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({ video: { width: 640 }, audio: false })
    } catch (e) {
      if (this.hasButtonTarget) this.buttonTarget.textContent = "camera blocked"
      return
    }
    this.video = document.createElement("video")
    this.video.muted = true
    this.video.playsInline = true
    this.video.srcObject = this.stream
    await this.video.play()
    this.canvas = document.createElement("canvas")
    this.on = true
    this.render()
    this.scheduleNext()
  }

  stop() {
    this.on = false
    clearTimeout(this.timer)
    if (this.stream) this.stream.getTracks().forEach((t) => t.stop())
    this.render()
  }

  scheduleNext() {
    if (this.on) this.timer = setTimeout(() => this.capture(), this.intervalValue)
  }

  async capture() {
    if (!this.on || !this.video.videoWidth) { this.scheduleNext(); return }
    try {
      const w = 512
      const h = Math.round(w * (this.video.videoHeight / this.video.videoWidth))
      this.canvas.width = w
      this.canvas.height = h
      this.canvas.getContext("2d").drawImage(this.video, 0, 0, w, h)
      const frame = this.canvas.toDataURL("image/jpeg", 0.6)
      await fetch(this.urlValue, {
        method: "POST",
        headers: { "Content-Type": "application/json", "X-CSRF-Token": this.csrf },
        credentials: "same-origin",
        body: JSON.stringify({ frame })
      })
    } catch (e) {
      /* transient — try again next cycle */
    }
    this.scheduleNext()
  }

  render() {
    if (this.hasIndicatorTarget) this.indicatorTarget.style.display = this.on ? "inline-flex" : "none"
    if (this.hasButtonTarget) this.buttonTarget.textContent = this.on ? "Camera on" : "Enable camera"
  }

  get csrf() {
    return document.querySelector('meta[name="csrf-token"]')?.content
  }
}
