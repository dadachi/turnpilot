# STATUS — TurnPilot

> The overnight loop appends to this every cycle. Keep it short and current so a
> human can triage in ~5 minutes at wake-up. Newest cycle on top.

## At-a-glance
- **Build health:** tests ✅ 13 runs / 29 assertions (Order math + advisory trigger) · main ✅ green · local Gemma 4 ✅ reachable
- **v1 walk-away-risk path:** ✅ working end-to-end (seed → flag → Gemma advisory → Turbo console → Accept/Override)
- **Demo replayable from `synthetic_rush.json`:** ✅ yes (`Replayer.seed` + `Replayer.tick`; visit `/` and "Run rush")

## v1 acceptance checklist
- [x] Rails app boots (8.1.3 / Ruby 4.0.5); Postgres; UUID PKs; Tailwind (Palette 9)
- [x] Replayer seeds the rush from `synthetic_rush.json` into Order records
- [x] Situational model: **cook-time overrun** walk-away risk vs baseline (`Order#flagged?`; prepared→now dwell)
- [x] Local Gemma 4 advisory via `GemmaClient` (Ollama /api/chat, think:false, format:json)
- [x] Advisory streams to console via Turbo; Accept/Override buttons render
- [x] **Override suppresses similar advisories + feeds back a learned threshold** — `ShopThreshold` + suppression window (`Advisory::SUPPRESSION_WINDOW`)
- [x] **Real-time ticking replayer** — `console#tick` + Stimulus `replay_controller` poll; rush plays out live via Turbo
- [x] **Tests** for `Order` math (9) + advisory trigger (4, Gemma+broadcast stubbed, offline)
- [x] Tighten Gemma prompt so `advise` is a strict boolean — prompt hardened + `advise?` coercion; `advise:false` now vetoes the alert
- [x] Sound on new advisory (WebAudio chime) + compact live queue strip (both UI — need morning smoke-test)

## Next breadth (after v1 is solid)
open-a-server advisory · ETA-to-customer · no-show re-notify · baseline from stats.

## Blockers / questions for the human (read first)
- **Morning smoke-test (browser + Ollama):** the live ticking demo, queue strip, and
  advisory chime are test-covered server-side but **not visually verified**. Run `bin/dev`,
  open `/`, click "Run rush", confirm advisories stream in with a chime and the queue strip
  updates. (5-min check.)
- **Breadth-item honesty (before building them):** under the real model, some planned
  breadth items need signals MyTurnTag doesn't record —
  - `open-a-server` (throughput drop → open a prep station): ✅ honest (uses `completed_at`
    rate + cooking count).
  - `ETA-to-customer`: only honest as **remaining cook time** for an in-progress order
    (baseline − elapsed); a pre-cook ETA is impossible (no join).
  - `no-show re-notify`: ⚠️ **not feasible** — `completed` = cooking finished, and pickup is
    NOT tracked, so there's no signal that a ready order went uncollected. Needs a product
    decision (add a pickup/handover event?) before it can be built honestly.
  - "baseline from stats": already done as `Order.baseline_cook_seconds` (avg real cook time).

## Cycle log (newest first)
### Visible learning (2026-07-04) — surface learned threshold/baseline in console
Status strip now shows "normal cook ~Xm · alerts after ~Ym" for the demo shop, where Y =
baseline × the learned `ShopThreshold` multiplier. Each Override raises Y (broadcast on the
next tick), so staff SEE the copilot adapt — closes the demo-script "agent adapts" beat.
Added read-only `ShopThreshold.multiplier_for` (no row creation, view-safe). +1 test → 49
green. UI — **needs morning smoke-test**.

### ETA-to-customer (2026-07-04) — breadth #2 (honest = remaining cook time)
`Order#eta_seconds`/`#eta_minutes` = time left to the shop's normal cook time (0 when
overdue, nil when not cooking) — the only honest ETA (no pre-cook ETA without a join). Queue
strip now shows a live countdown per chip ("~Xm left" → "overdue"), using each shop's learned
baseline. +3 tests → 48 green. UI — **needs morning smoke-test**.

### Open-a-server advisory (2026-07-04) — breadth #1 ✅ (2nd advisory type)
`OpenServerAdvisor`: when a shop's backlog (`cooking_count`) ≥ 5 and exceeds recent
completions (falling behind), asks Gemma for a shop-level `open_server` advisory (order-less),
with its own window suppression + advise-veto. Hooked into `Replayer.tick` per shop. Shared
`Advisory.advise?` coercion (refactored out of AdvisoryGenerator). Demo fires it at the anchor
(5 cooking vs 4 completed) alongside walk-away. +5 tests → 45 green.

### Throughput signals (2026-07-04) — open-a-server groundwork
`Order.cooking_count(shop_id)` (backlog, via a `cooking_at` scope — prepared & not completed,
join-independent) and `Order.completions_in(shop_id, window)` (rolling throughput). Both from
staff timestamps only, so honest. +2 tests → 40 green. Next: `OpenServerAdvisor` uses these
(backlog high + throughput can't clear it → Gemma → shop-level `open_server` advisory).

### Shop-scoped advisories (2026-07-04) — breadth prep for open-a-server
Advisories can now be shop-level: added `advisories.shop_id`, made `order_id` nullable,
`belongs_to :order, optional: true`. `AdvisoryGenerator` stamps `shop_id`; the card shows
"kitchen" when there's no order. Unblocks the `open_server` advisory (a shop-level, not
per-order, signal). +2 tests → 38 green. Next: `OpenServerAdvisor` (throughput/backlog → Gemma).

### Advisory chime (2026-07-04) — completes the last v1 checklist item ✅
`chime_controller` (Stimulus) on #advisories: a MutationObserver plays a short synthesized
WebAudio beep (rising 880→1320 Hz, no asset, offline) when a new advisory is prepended.
Audio unlocks on the "Run rush" click. **v1 checklist now fully checked off.** UI/audio —
needs a morning browser smoke-test. Next: breadth items (open-a-server, ETA, no-show).

### Compact live queue strip (2026-07-04) — queue-strip half of the last v1 item
`console/_queue` partial: chips for each cooking order (`#N · Xm`), flagged ones in advisory
pink, sorted by cook time; broadcast on each `tick` alongside status. Rendered on index.
Tests green (36). UI-only — **needs a morning browser smoke-test**. Chime/toast on new
advisory still to do (the other half of this checklist item).

### Strict-boolean Gemma advise gate (2026-07-04)
Hardened the Gemma prompt (advise must be a JSON boolean, JSON-only, snake_case action) and
added `AdvisoryGenerator#advise?` coercion — `advise:false`/"no" now vetoes the alert (no
advisory, no broadcast), while ambiguous values still default to advising so a fuzzy response
never drops a real one. +2 tests → 36 green.

### Ticking replayer — live driver (2026-07-04) — real-time replay step 2/2 ✅ complete
`console#tick` advances the sim (`Replayer.tick` on wall-clock `now`) and broadcasts the
refreshed status strip; a Stimulus `replay_controller` polls it every 4s, so the seeded rush
plays out live and advisories stream in over Turbo. Extracted `console/_status` partial
(cooking / at-risk counts). +2 controller tests (tick makes no Gemma call when nothing's
flagged). 34 green. **Real-time replayer item checked off.** NOTE: browser-side polling not
yet visually verified (no live app/Ollama run this cycle) — smoke-test in the morning.

### Model pivot 2/2 (2026-07-04) — data-driven baseline + DESIGN corrected
`Order.baseline_cook_seconds(shop_id)` = avg(`completed_at − prepared_at`) over recent
completed tags, fallback to the constant under `min_samples`. Wired into `Replayer.tick`
(memoized per shop) and the Gemma snapshot, so "vs this shop's normal" is real data (demo
baseline ≈ 5.3 min, still flags the 3 slow cooks). Rewrote `docs/DESIGN.md` event-stream +
situational-model sections to the real MyTurnTag (modes, states, `prepared`=cook-start, no
join, honest baseline). +3 tests → 32 green. **Model pivot complete.**

### MODEL PIVOT (2026-07-04) — honest metric: cook-time overrun (step 1/2)
Domain-expert (user) established MyTurnTag reality: **no join event**, `idled` = pre-created
tag (no signal), `customer_read` unreliable, `Shop.mode` gates the lifecycle, and `prepared`
= "cooking started" / `completed` = "cooking finished". So the only honest real-time signal
(preparing_mode only) is a tag **cooking too long**: `Order` risk now = `prepared→now` dwell
vs baseline cook time (was the fictional join→prepared wait). Rewrote Order math
(`cook_seconds`/`cooking?`/`flagged?`/`walk_away_risk` with a `baseline:` arg), updated the
Gemma snapshot/prompt, and regenerated the fixture (`gen_synthetic_rush.rb`) so 3 orders
overrun at the anchor. Fixed a bug: cook_seconds must cap at `now` (scripted completed_at is
future during replay). See memory `myturntag-data-model-reality`. 29 tests green.
NEXT (step 2/2): per-shop baseline from avg(completed cook time); rewrite docs/DESIGN.md to the real model.

### Ticking replayer core (2026-07-04) — real-time replay step 1/2
`Replayer.seed` now stores each order's full time-shifted timeline (incl. future joins);
`Order#materialized_status`/`#materialize!` derive status from timestamps; `Replayer.advance(now)`
re-materializes all orders as the clock moves; timeline-aware `Order.live(t)` scope
(joined & not completed by t). `tick` advances first. Fixed 2 latent bugs: demo reset hit
an advisories FK (now clears advisories first) and waiting orders weren't persisted. +4 tests.
Next (2/2): a driver (Stimulus poll → tick endpoint + Turbo broadcast) so it plays out live.

### Override suppression window (2026-07-04) — Override step 4/4 ✅ feature complete
`Advisory::SUPPRESSION_WINDOW` (5 min); `Order#suppressed?` is true for a recent same-kind
**override** only (ignores accepts + other kinds). `AdvisoryGenerator` early-returns nil
(no Gemma call) and `Replayer.tick` skips suppressed orders — so a rejected advisory stays
quiet for the window. +3 tests. **v1 Override item now checked off.** Next: real-time ticking replayer.

### Accept/Override feed back to the threshold (2026-07-04) — Override step 3/4
`AdvisoriesController#accept` now calls `record_accept!` and `#override` calls
`record_override!` on the order's `ShopThreshold` — closing the learning loop (reject →
advise less; accept → drift back). +2 controller tests (integration; broadcast renders
fine). Next (4/4): suppression window so an override quiets similar advisories for a period.

### Wire learned threshold into situational model (2026-07-04) — Override step 2/4
`Order#flagged?`/`#walk_away_risk` now take a `threshold:` multiplier (defaults to the
baseline constant, so existing behavior is unchanged). `Replayer.tick` resolves each
shop's learned `ShopThreshold.risk_multiplier` (memoized per shop) and flags/ranks with
it — so a raised threshold advises less. +1 test (raised threshold un-flags a borderline
order). Next: override suppression window + controller feeds Accept/Override back to the threshold.

### Learned-threshold model (2026-07-04) — Override foundation (step 1/4)
Added `ShopThreshold` (uuid, per-shop `risk_multiplier`, override/accept counts) +
migration. `record_override!` raises sensitivity (advise less), `record_accept!` drifts
back toward baseline; clamped [1.0, 4.0]. 5 tests. Not yet wired into `Order#flagged?` —
next: pass the learned multiplier into the situational model + the override suppression window.

### Tests (2026-07-04) — first real coverage on the demo path
`test/models/order_test.rb` (9): `wait_seconds`, `walk_away_risk`, `flagged?` incl. the
540s/9-min boundary, `wait_minutes` — in-memory `Order.new` + fixed `NOW`, no DB/Ollama.
`test/services/advisory_generator_test.rb` (4): advisory persisted from Gemma result,
Turbo broadcast target, missing-key degradation, and error → nil/no-persist — `GemmaClient`
+ broadcast swapped out (Minitest 6 dropped `Object#stub`, so a small singleton-swap helper).
CI `test` job now runs 13 tests instead of 0. Also wrote README + repo about.

### Ops (2026-07-04) — Dependabot bumps merged + CI fix + main protected
Merged all 4 Dependabot PRs: `image_processing` 1.14→2.0.2 (unused gem, no-op),
GH Actions `checkout` 6→7, `cache` 4→6, `upload-artifact` 4→7. They were all red on a
**pre-existing `main` bug** (not the bumps): CI ran `test:system` with no `test/system`
dir → `LoadError`, plus a rubocop offense in `gemma_client.rb`. Fixed both in PR #5
(added `test/system/.keep`; autocorrected bracket spacing). Then protected `main`:
required status checks gate bot PRs, but `enforce_admins:false` + no required reviews
so the overnight direct-to-`main` loop is untouched; repo auto-merge enabled.

### Cycle 0 (kickoff, ~19:xx JST) — v1 slice built + verified in browser
Scaffold (Rails 8.1.3, Tailwind Palette 9, Postgres, UUID) → GemmaClient → Order/Advisory
models → Replayer → Turbo console. Verified live: real Gemma advisory streamed with
Accept/Override. Fixed a mixed vendor/bundle (Ruby 4.0.1↔4.0.5) so `bin/rails` is reliable.
