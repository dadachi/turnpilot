# TurnPilot

**A live queue-ops copilot for walk-in shops.** TurnPilot watches a streaming NFC
queue-event feed, builds a situational model of who's waiting, and turns it into
**plain-language advisories** with a one-tap **Accept / Override** loop. All reasoning
runs on **local Gemma 4 via Ollama — offline, on-device, privacy-first**. No cloud calls.

It is deliberately **not a dashboard**: the product is the advisory + accept/override
loop, not a wall of charts.

> Built entirely during the event. See [`docs/DESIGN.md`](docs/DESIGN.md) for the full
> design spec and [`STATUS.md`](STATUS.md) for current build status.

## How it works

```
NFC event feed ──▶ Replayer ──▶ Order situational model ──▶ flagged? ──▶ AdvisoryGenerator
(synthetic_rush.json)            (wait / walk-away-risk)                        │
                                                                    Gemma 4 (Ollama /api/chat)
                                                                                │
                                          Turbo Stream ──▶ Console (Accept / Override)
```

- **Situational model** — `Order` computes per-order wait time and a `walk_away_risk`
  vs. the shop baseline; `Order#flagged?` fires when a customer waits past the threshold
  (baseline 6 min × 1.5 = **9 min**).
- **Reasoning** — `AdvisoryGenerator` builds a snapshot for a flagged order and asks
  `GemmaClient` (local Gemma 4) for one short, actionable advisory as JSON.
- **Delivery** — the advisory is broadcast to the console over Turbo Streams; staff
  **Accept** or **Override** it.
- **Reproducible demo** — a deterministic `Replayer` seeds a fixed rush from
  `synthetic_rush.json`, so the live demo is repeatable.

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
