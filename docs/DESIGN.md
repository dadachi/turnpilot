# TurnPilot — Design Spec (Google Remote / local Gemma / MyTurnTag)

Working spec for the hackathon build. This is a **planning doc**; the submission repo and
all code start at kickoff (Sat 7:00 PM JST). TurnPilot is **new work that integrates with**
MyTurnTag — it does **not** reuse MyTurnTag's code.

## Event stream (derived from MyTurnTag's data model, not its code)

MyTurnTag is an **order-ready queue**. Each number tag (`item_tags`) moves through a
lifecycle logged in `item_tag_histories`. TurnPilot consumes a normalized event per
transition through a **thin adapter interface** — the source behind it is swappable, so
**MyTurnTag itself needs no modification**:

- **Replayer** → the demo (v1). MyTurnTag untouched (also required by the rules).
- **Poll / tail** → production, *zero-touch*: `item_tag_histories` is append-only, so
  TurnPilot can poll MyTurnTag's read API or tail that table read-only.
- **Webhook** → production, real-time: the *only* option that adds code to MyTurnTag —
  an optional future upgrade, not required.

Normalized event:

```
{ shop_id, queue_number, event, at, actor }        # actor: customer | staff
event ∈ { joined, prepared, customer_read, completed }
```

| event | MyTurnTag source field | meaning |
|---|---|---|
| `joined` | `item_tags.created_at` (+ `queue_number`) | customer pulls a tag, enters the queue |
| `prepared` | `prepared_at` / `prepared_by_id` | staff marks the order ready |
| `customer_read` | `customer_read_at` | customer viewed the "ready" notice |
| `completed` | `completed_at` / `completed_by_id` | order handed over / done |

**Baseline** comes from `stats_averages` (per shop, per `day_of_week`: `scanned_num`,
`prepared_num`, `completed_num`) → derive this shop's typical time-to-prepared and
throughput. This is what "vs THIS shop's normal" means.

## Situational model (recomputed on each event)

- `open_orders` = joined and not completed
- per order: `wait_to_prepared` (joined→now if not prepared), `wait_to_pickup`
  (prepared→now if prepared and not read/completed)
- `throughput` = completions in a rolling window
- `walk_away_risk(order)` = f(wait vs baseline time-to-prepared; prepared-but-unread age)

## The agent (reasons on local Gemma — Google Remote track requirement)

Input: situational-model snapshot + the flagged order + baseline + recent overrides.
Output: `{ advise: bool, text, rationale, suggested_action }`.
The override adjusts a per-shop learned threshold (stop advising what staff reject).

## v1 — the ONE end-to-end path that MUST work by wake-up (7:00 AM JST)

**Walk-away-risk advisory.** Replayer streams events → an order's `wait_to_prepared`
exceeds the baseline/learned threshold → agent (via local Gemma) emits a plain-language
advisory with rationale → streamed to the operator UI (Turbo Streams) with **[Accept] /
[Override]** → Override suppresses similar advisories for a window and is logged and fed back.

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
