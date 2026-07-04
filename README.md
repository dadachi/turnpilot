# TurnPilot

**A live queue-ops copilot for walk-in shops.** TurnPilot watches a streaming NFC
queue-event feed, builds a situational model of the kitchen, and turns it into
**plain-language advisories** with a one-tap **Accept / Override** loop. All reasoning
runs on **local Gemma 4 via Ollama — offline, on-device, privacy-first**. No cloud calls.

It is deliberately **not a dashboard**: the product is the advisory + accept/override
loop, not a wall of charts.

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
                                     Turbo Stream ──▶ Console (Accept / Override · learns)
```

- **Situational model** — `Order#cook_seconds` = `prepared → now` (frozen at `completed`);
  `Order#flagged?` fires when cook time exceeds the shop's **learned** baseline cook time
  (`avg(completed − prepared)`) × a per-shop sensitivity multiplier.
- **Two advisory types** — `AdvisoryGenerator` (per-order **walk-away risk** from cook
  overrun) and `OpenServerAdvisor` (shop-level **open-a-server** when the cooking backlog
  outpaces recent completions). Both ask `GemmaClient` (local Gemma 4) for one short JSON advisory.
- **Learning loop** — staff **Accept** / **Override** each advisory; Override raises the
  shop's sensitivity (advise less) and suppresses similar advisories for a window, and the
  console shows the "alerts after ~Ym" threshold moving as it adapts.
- **Live & reproducible** — a deterministic `Replayer` seeds a fixed rush from
  `synthetic_rush.json` and a Stimulus poller ticks the clock, so the rush plays out live
  and the demo is repeatable. The queue strip shows each cooking order's ETA countdown.

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
