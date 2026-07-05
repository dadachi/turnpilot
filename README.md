# TurnPilot

**▶ [Watch the demo](https://youtu.be/5K_dsMP1AqY)** · [Design spec](docs/DESIGN.md) · [Build status](STATUS.md)

**A live copilot for walk-in shops — it spots late orders and tells staff what to do.**
TurnPilot watches a streaming NFC queue-event feed, builds a situational model of the
kitchen, and turns it into **plain-language advisories** with a one-tap **Accept / Dismiss**
loop. All reasoning runs on **local Gemma 4 via Ollama — offline, on-device, privacy-first**.
No cloud calls.

It is deliberately **not a dashboard**: the product is the advisory + accept/dismiss
loop, not a wall of charts. The console reads top-to-bottom as a story — a plain-language
situation line ("3 orders running late — a customer is waiting at the counter"), the live
queue, then the advice.

> Built entirely during the event. See [`docs/DESIGN.md`](docs/DESIGN.md) for the full
> design spec and [`STATUS.md`](STATUS.md) for current build status.

## The honest signal

MyTurnTag records only **staff** actions on a tag — `prepared` (cooking started) and
`completed` (cooking finished). There is **no recorded "customer joined" event** (tags are
pre-provisioned), so TurnPilot never models a pre-cook wait. The one trustworthy real-time
signal is **cook-time overrun**: an order that's been cooking longer than this shop's normal
→ the waiting customer may walk away. (See [`docs/DESIGN.md`](docs/DESIGN.md) for the full
data-model rationale, and applies to shops in `preparing_mode`.)

## How it works

```
NFC event feed ──▶ Replayer ──▶ Order situational model ──▶ flagged? ──▶ Advisor ──▶ Gemma 4
(synthetic_rush.json)  (ticks)   (cook overrun · throughput)             │      (Ollama /api/chat)
                                                                         ▼
                                     Turbo Stream ──▶ Console (Accept / Dismiss · learns)
```

- **Situational model** — `Order#cook_seconds` = `prepared → now` (frozen at `completed`);
  `Order#flagged?` fires when cook time exceeds the shop's **learned** baseline cook time
  (`avg(completed − prepared)`) × a per-shop sensitivity multiplier.
- **Advisory types** — per-order **🧾 walk-away risk** (`AdvisoryGenerator`, from cook
  overrun) and shop-level **🍳 capacity / open-a-server** (`OpenServerAdvisor`, when the
  cooking backlog outpaces recent completions); the camera adds more (below). A scope icon
  marks per-order vs whole-kitchen at a glance. Each asks `GemmaClient` (local Gemma 4) for
  one short JSON advisory in plain, human language.
- **Learning loop** — staff **Accept** (act on it) or **Dismiss** (not needed) each advisory;
  Dismiss raises the shop's sensitivity so it advises less on similar situations and suppresses
  them for a window — a toast confirms, and the console's "alerts after ~Ym" threshold visibly
  climbs as it adapts. A completed order's unactioned advisory **auto-resolves** so the advice
  list stays in sync with the live queue.
- **Speaks up (opt-in)** — a **Read aloud** toggle speaks each new advisory via the browser's
  offline text-to-speech, so heads-down staff hear it; the reasoning is still on-device Gemma.
- **Live & reproducible** — a deterministic `Replayer` seeds a fixed rush from
  `synthetic_rush.json` and a Stimulus poller ticks the clock, so the rush plays out live
  and the demo is repeatable. The queue strip shows each cooking order's time and minutes over
  normal (`#3 · 9.9m · +4.5m over`) or its ETA countdown.

## Camera vision (capstone) — on-device Gemma perception

MyTurnTag records no "customer joined" signal, so TurnPilot can't otherwise tell who's
*waiting*. An **opt-in counter camera**, read by the **multimodal** `gemma4:e4b` **on-device**
(the same offline Gemma, `images:[…]` on `/api/chat`), supplies exactly that — as a coarse,
privacy-safe signal (`people_present`, a `none|light|busy` band; **never a count**, never a
stored frame). It feeds the *same* advisory loop:

- a borderline cook **escalates** when a customer is visibly waiting,
- a **queue-building** nudge when a line forms but nothing's cooking,
- a **walk-away** advisory when a waiting customer leaves while an order is still overrunning.

It's a background perception input, not an image analyzer — the advisory loop stays the
product. Full design in [`docs/vision-capstone-spec.md`](docs/vision-capstone-spec.md). The
console's **Simulate camera** controls reproduce each beat deterministically (no live camera
needed), matching the replayer's reproducibility.

## Stack

Rails 8.1 · Ruby 4.0 · PostgreSQL (UUID primary keys) · Hotwire (Turbo Streams / Solid
Cable) · TailwindCSS v4 (`tailwindcss-rails`, no Node) · Minitest · local **Gemma 4** via
Ollama's native `/api/chat`.

## Getting started

### Prerequisites
- Ruby 4.0.5 (see `.ruby-version`) and PostgreSQL running locally.
- [Ollama](https://ollama.com) with the Gemma 4 model pulled:
  ```bash
  ollama pull gemma4:e4b
  ```

### Setup & run
```bash
bin/setup            # installs gems, prepares the database
bin/dev              # starts the Rails server + Tailwind watcher
```
Open http://localhost:3000 and click **Run rush** to seed the demo feed and watch
advisories stream in.

### Configuration
Gemma connection is env-configurable (defaults shown):
```
GEMMA_ENDPOINT=http://localhost:11434
GEMMA_MODEL=gemma4:e4b
```

## Tests
```bash
bin/rails test        # unit + service tests (offline; Gemma is stubbed)
bin/rubocop           # style
```
The advisory tests stub `GemmaClient` and the Turbo broadcast, so the suite runs fast and
offline — no Ollama required.

## Reasoning notes (Gemma 4)
Gemma 4 is a reasoning model, so `GemmaClient` uses Ollama's **native `POST /api/chat`**
(not the OpenAI `/v1` endpoint) with **`think: false`** (otherwise `content` comes back
empty) and **`format: "json"`** for clean, parseable output. Instructions go in the user
turn (no `system` role).
