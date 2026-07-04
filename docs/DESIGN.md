# TurnPilot — Design Spec (Google Remote / local Gemma / MyTurnTag)

Working spec for the hackathon build. This is a **planning doc**; the submission repo and
all code start at kickoff (Sat 7:00 PM JST). TurnPilot is **new work that integrates with**
MyTurnTag — it does **not** reuse MyTurnTag's code.

## Event stream (derived from MyTurnTag's REAL data model, not its code)

MyTurnTag is an **order-ready queue**. Each number tag (`item_tags`) moves through a state
lifecycle logged in `item_tag_histories`. **The lifecycle depends on `Shop.mode`:**

- `preparing_mode`: `idled → prepared → completed`
- `normal_mode`:    `idled → completed` (no `prepared` step)

What the states actually mean — this is the crux, and earlier drafts of this spec got it wrong:

| state | set by | meaning | reliable? |
|---|---|---|---|
| `idled` | system | tag exists — but tags are **pre-created regardless of any customer** | ❌ no signal (may be empty stock on the rack) |
| `prepared` | staff | **cooking/preparation has STARTED** | ✅ staff action |
| `completed` | staff | **cooking finished** (order ready) | ✅ staff action |
| `customer_read` | customer | customer opened the "ready" notice | ⚠️ customer-controlled — a weak *positive* only, never a negative |

**There is no "joined" event.** Pulling an NFC tag is not recorded, and `idled` is
pre-provisioned, so *nothing marks a customer entering the queue*. The only trustworthy
timestamps are the two staff transitions: `prepared_at` (cook start) and `completed_at`
(cook done). We therefore never model a pre-cook wait.

TurnPilot consumes these transitions as a normalized stream through a **thin adapter** —
swappable, so **MyTurnTag itself needs no modification**:

- **Replayer** → the demo (v1). MyTurnTag untouched (also required by the rules).
- **Poll / tail** → production, *zero-touch*: `item_tag_histories` is append-only.
- **Webhook** → production, real-time: the only option that adds code to MyTurnTag; optional.

**Baseline = this shop's normal cook time**, learned honestly as the average
`completed_at − prepared_at` over recent completed tags (`Order.baseline_cook_seconds`),
falling back to a constant until there's enough signal. That is what "vs THIS shop's normal"
means — derived from recorded staff timestamps, not assumed.

## Situational model (recomputed on each event)

The only honest real-time signal is the **cooking window**, so the model keys off it
(`preparing_mode` shops):

- `cooking` = tags `prepared` but not yet `completed`
- per order: `cook_seconds` = `prepared → now` (frozen at `completed`)
- `throughput` = completions in a rolling window (from `completed_at`)
- `walk_away_risk(order)` = `cook_seconds` ÷ (baseline cook time × learned per-shop
  threshold). A tag cooking past this shop's normal → the waiting customer may walk away.

`normal_mode` shops have no `prepared` state and thus no live at-risk signal, so TurnPilot's
real-time advisory is inherently a **`preparing_mode`** feature.

## The agent (reasons on local Gemma — Google Remote track requirement)

Input: situational-model snapshot + the flagged order + baseline + recent overrides.
Output: `{ advise: bool, text, rationale, suggested_action }`.
The override adjusts a per-shop learned threshold (stop advising what staff reject).

## v1 — the ONE end-to-end path that MUST work by wake-up (7:00 AM JST)

**Walk-away-risk advisory.** Replayer streams events → an order's cook time
(`prepared → now`) exceeds this shop's baseline cook time × its learned threshold → agent
(via local Gemma) emits a plain-language advisory with rationale → streamed to the operator
UI (Turbo Streams) with **[Accept] / [Override]** → Override suppresses similar advisories
for a window and is logged and fed back into the threshold.

**Acceptance criteria**
- Deterministic replay reproduces the same advisory (fixed seed / fixed stream).
- A real local-Gemma call produces the advisory text + rationale.
- Advisory appears live in the UI; Accept and Override both work and are recorded.
- Tests cover the model math and the trigger condition.
- Main stays green; `STATUS.md` updated each cycle.

## Out of scope for v1 (breadth comes only after v1 is solid)

Real NFC hardware · live MyTurnTag integration (use the replayer) · auth / multitenancy ·
multi-shop · the other advisory types (re-notify unread, add-a-server on throughput drop,
predicted wait for new joiners) · native mobile · anything resembling a metrics **dashboard**.

## Console, auth, deployment

- **Console** = one web screen (Rails + Hotwire), opened in a browser / installable PWA on
  the shop's counter tablet or phone. Content: the live **advisory stream** (card + rationale
  + [Accept] / [Override], chime/toast on arrival) plus a **compact queue strip** as context.
  Deliberately not a dashboard — the advisory loop is the centerpiece.
- **Auth (v1)** = per-shop **signed device link / short shop code** (device pairing). No
  passwords, no per-user accounts. Not a shortcut: the situational model needs shop scope
  anyway. **Deferred to v2/production:** per-user identity, roles, multi-tenant login — in
  production these ride MyTurnTag's existing accounts/roles (not rebuilt or copied here).
- **Stack:** Rails 8.1 + Hotwire (Turbo Streams / ActionCable over Solid Cable) · Postgres ·
  Minitest · deterministic event replayer.
- **Deployment — fully local / offline (Google Remote track).** Reasoning runs on **Gemma 4**
  locally via **Ollama** (`ollama pull gemma4:e4b`; `e2b`/`e4b` = edge/on-device variants, also
  `12b`/`26b`/`31b`). App + inference on one machine (the shop's device) — offline, privacy-first.
- **⚠️ Gemma 4 integration (verified in spike):** Gemma 4 is a **reasoning model** — call Ollama's
  **native `POST /api/chat`** (NOT the OpenAI `/v1` endpoint) with **`think:false`** (disable
  chain-of-thought — else `content` is empty) and **`format:"json"`** (clean parseable JSON, no
  fences). Parse `message.content`. This gives ~2.6s advisories. Body:
  `{model, stream:false, think:false, format:"json", messages:[{role:"user", content}], options:{temperature, num_predict}}`.
  Gemma has no separate `system` role — put instructions in the user turn.
- **Optional v2 (sponsor):** speak advisories aloud via **Gradium TTS** (145K credits, +100K
  with code `RAISE-2026`) so heads-down staff hear the alert. Nice-to-have, not v1.

## Conventions

- **Colors: Palette 9 "Friendly"** (`docs/palette-9.md` — Refactoring UI ramps; MyTurnTag ships
  the same file). Semantic mapping → **Light Blue** = primary/structure, **Pink** = the
  advisory/alert signal, **Green** = Accept/success, **Red** = danger, **Yellow** = warning,
  **Cool Grey** = text/neutrals/backgrounds.
- **CSS: TailwindCSS v4** via `tailwindcss-rails` (standalone CLI, **no Node build** — same as
  CommitJobs). Palette 9 wired as `@theme` tokens in `app/assets/tailwind/application.css`
  (v4 CSS-first config); use as utilities (`bg-brand-500`, `bg-advisory-500`, `text-ink`).
- **UUID primary keys on all TurnPilot tables** (matches MyTurnTag; non-enumerable IDs suit
  the signed device-link auth). Set app-wide via generators `primary_key_type: :uuid` +
  `enable_extension "pgcrypto"`.
- **External references are loose, not foreign keys.** Columns holding MyTurnTag identifiers
  (`shop_id`, tag ref) are plain `uuid` — no `foreign_key` constraint (separate DB; MyTurnTag
  is never touched).

## Demo script (1 min, real footage)

Replay a simulated rush → queue builds → walk-away-risk advisory streams in → staff taps
Override once (agent adapts) then Accept → "walkaways prevented" closing beat.
