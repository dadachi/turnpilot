# STATUS — TurnPilot

> The overnight loop appends to this every cycle. Keep it short and current so a
> human can triage in ~5 minutes at wake-up. Newest cycle on top.

## At-a-glance
- **Build health:** tests ✅ 55 runs / 140 assertions · main ✅ green · local Gemma 4 (needs Ollama up)
- **v1 walk-away-risk path:** ✅ end-to-end (seed → cook-overrun flag → Gemma advisory → Turbo console → Accept/Override → learns)
- **Advisory types:** walk-away-risk (per-order cook overrun) + open-a-server (shop throughput). ETA countdown in the queue strip.
- **Demo replayable from `synthetic_rush.json`:** ✅ (`Replayer.seed` + ticking `Replayer.tick`; visit `/`, click "Run rush")
- **✅ Browser smoke-test done (2026-07-05):** live demo verified end-to-end with real Gemma + Ollama — both advisory
  types stream in, queue strip counts down (ETA), Override raised "alerts after" 7.9m→8.7m. Found + fixed 2 bugs
  (duplicate advisories from overlapping ticks; Override crash on order-less advisories). No console errors.

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
- **Smoke-test: DONE ✅ (2026-07-05)** — verified live in-browser with real Gemma. (One thing
  to eyeball yourself: the WebAudio *chime* can't be asserted headlessly — confirm you hear it
  when an advisory arrives.)
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
### Fix: Accept now suppresses re-alerts on the same order (2026-07-05)
Reported: accept an order's advisory, and a fresh "Delay risk (order #N)" reappears a tick later.
Cause: `Order#suppressed?` only counted *overridden* (dismissed) advisories, so after Accept the
order had no pending advisory and wasn't suppressed — still cooking + still over threshold → the
next `walk_away` tick re-fired. Fix: `suppressed?` now treats a recently **handled** advisory —
Accepted *or* Dismissed — as suppressing (created within `SUPPRESSION_WINDOW`). The learning
difference stays (Accept lowers the threshold, Dismiss raises it); both just get a quiet window.
Updated the suppression tests (accept now suppresses; pending/resolved/other-kind don't) + live-
verified (accept → suppressed?=true → next tick adds nothing). 95 tests green.

### Refresh README + GitHub "about" (2026-07-05)
Brought the public docs current: Accept/**Override** → Accept/**Dismiss** everywhere; plainer
one-liner ("spots late orders and tells staff what to do"); noted the narrative-spine console,
scope-icon advisory types (🧾 per-order / 🍳 whole kitchen), the visible learning loop + toast,
auto-resolve on completion, the queue "+Xm over" chip, and the opt-in Read-aloud. GitHub repo
description updated to match via `gh repo edit`.

### Distinguish shop-wide vs per-order advisories with a scope icon (2026-07-05)
"whole kitchen" (shop-level) and "order #N" (per-order) advisories looked near-identical — same
pink stripe, only small grey corner text differed. Added a scope cue: the subject is now a small
pill with an icon — 🍳 whole kitchen vs 🧾 order #N — so the two read distinctly at a glance
(same in the collapsed handled row). Kept pink for all (they're all act-now alerts); did NOT use
color for scope because blue reads as "on-track/calm" elsewhere and would missignal. No mobile
overflow (390px checked). 94 tests green.

### Drop the newest-card focus ring (arbitrary, read as inconsistent) (2026-07-05)
The top pending card had a full pink focus ring (`first:ring`) while the rest had only the pink
left-stripe — reported as confusing ("why is that one all pink?"). The ring marked *newest*, not
*most urgent* (e.g. it sat on order #3 while order #1 was further overdue), so it looked like a
priority cue but wasn't. Removed it: every pending card now looks identical (pink left-accent =
act now); recency is already conveyed by top position. 94 tests green.

### Rename the "Override" button to "Dismiss" (2026-07-05)
"Override" was the least clear label on the screen — it didn't say what it does (dismiss the
alert) and could be misread as "override the system." Renamed the UI button "Override" → "Dismiss"
+ a tooltip ("tells TurnPilot this wasn't worth alerting on, so it alerts less next time"); the
collapsed handled row now reads "dismissed"; the status-strip tooltip says "each time staff
Dismiss an alert." INTERNAL names unchanged (status `overridden`, `override_advisory_path`,
`record_override!`) — no code churn, no route change. Verified live: buttons read Accept/Dismiss,
dismissing collapses to "… dismissed" and still raises the threshold + toasts. Pitch note: call
it the "Accept/Dismiss loop." 94 tests green.

### Clarify the shop-level CAPACITY advisory (2026-07-05)
The shop-level (order-less) advisory was labeled just "kitchen" (the fallback subject when an
advisory has no order) and its rationale was numbers-soup ("Cooking (5) exceeds completions (4),
and the rate is above baseline (5.3)"). Relabeled the subject "kitchen" → "whole kitchen" so it
reads clearly as the whole-shop counterpart to "order #N", and rewrote the OpenServerAdvisor
rationale prompt to plain English + temp 0.5. Live-verified: rationale now "We are cooking more
orders than we are finishing, causing the wait times to grow" (advise fired 3/3). 94 tests green.

### Auto-resolve stale advisories when their order finishes cooking (2026-07-05)
Reported incoherence: an "order #1" advisory card lingered after #1 had left the Live Queue.
Cause: the Live Queue only shows *cooking* orders, but `tick` never retired the pending
advisory an order spawned — so once the order completed it dropped out of the queue while its
unactioned advisory stayed in "What TurnPilot advises," telling staff to chase a finished order.
Fix: new `resolved` Advisory status + `Replayer.resolve_stale(now)` (runs in `tick` after
`advance`) marks any pending, order-scoped advisory whose order is no longer cooking as resolved
and broadcasts the replace, so the pending card collapses live to a muted "✓ order #N · cleared ·
order done" row. Keeps the queue and the advice list in sync. +1 test (fire while cooking →
jump past completion → all resolved, 0 order-scoped pending). Verified live at offset −6m: queue
#11/#12 cooking, #1–3 collapsed as cleared. 94 tests green.

### Varied advisory rationale — kill the "if-statement" tell (2026-07-05)
The rationale prompt used to say *"cite the cook time vs the shop's normal"*, so at temp 0.2
every flagged order produced the identical template "The slow order (X min) significantly
exceeds the baseline cook time (5.3 min)" — a judge reads that as an `if (t > threshold)`, not
an LLM, undercutting the whole reasoning claim. Fix: added a distinct per-order anchor
`minutes_over_normal` to the snapshot; rewrote the rationale instruction to lead with a
concrete order-specific fact and VARY the opening/angle (minutes past normal · customer still
at counter · knock-on to the queue), explicitly banning stock openers and raw-number restatement;
nudged this call's temperature 0.2→0.5. Live-verified against real Gemma across 6 draws on the
flagged orders: **6/6 distinct, customer/queue-framed rationales, 0 advise-failures** (JSON
stayed valid, `advise` stayed true — no demo destabilization). JSON contract unchanged, and the
partial already hides a blank rationale, so there's no crash path. 90 tests green.

### Marketing pass — surface the offline-Gemma story + make learning visible (2026-07-05)
Fable (as marketer) reviewed the real rendered console. Shipped its top batch: (1) **header
offline badge** `● Offline · Gemma 4 on-device` + tagline + a per-advisory footer `Reasoned
locally by Gemma 4 · 0 cloud calls` — the track-winning differentiator was buried at the tail
of a grey status line; now it's the second thing you see and it's proven on every card.
(2) **Fixed the mobile header** (was a 3-line wrap colliding with the buttons; now title+badge
row, tagline, compact Camera/Read-aloud row). (3) **Recessed the demo scaffolding** into a
dashed "Demo controls" strip (Run rush + Simulate camera + a neutral "Live replay · Cafe"
chip) so the test rig no longer outranks the hero advisory; demoted "Cafe demo" out of the H1.
(4) **Override now shows the learning**: a toast "Got it — raising the alert threshold for this
shop." + the status strip re-broadcasts so "advising after ~Xm" visibly climbs (verified live:
7.9m→8.7m→9.5m→14.5m over four Overrides, and "at risk" 3→2 as a raised threshold un-flagged a
borderline order). New `toast_controller` + `_toast` partial; button labels shortened
(Camera / Read aloud). Verified via Playwright at 1280px + 390px + DOM-observed toast insertion.
90 tests green. UI-heavy — a morning click-through smoke-test is still worth doing.

### Spoken advisories + audio-input spike (2026-07-05)
Spike result (recorded so we don't retry it): **Ollama does NOT pass audio to `gemma4:e4b`** —
posting a spoken WAV/MP3 via `audio`/`audios` fields returns HTTP 200 but the model replies
"I cannot listen to any audio input." The listed "audio" capability isn't wired through the API
(unlike `images`, which works). So voice-*input* / Gemma-generated speech is out of scope.
Shipped the honest half instead: **spoken advisories** — an opt-in "🔊 Speak" toggle + a
`voice_controller` that watches the advisory list and reads each new card aloud via the
browser's offline `speechSynthesis`. Reasoning stays on-device Gemma; the voice is local
browser TTS (no cloud, no extra model). JS-only — **needs a morning browser smoke-test**
(toggle on, trigger an advisory, confirm it speaks once). 90 tests still green.

### Camera path verified live + camera-state indicator (2026-07-05)
Confirmed the FULL camera path on a real webcam: `getUserMedia` + "camera on" indicator +
frames POSTing every ~6s + real Gemma reading `present=true` with accurate notes → observations
flowing → **walk-away and escalated advisories fired from the real camera** ("Customer left
while an order is significantly delayed"; "a customer is waiting at the counter"). The last
manual smoke-test item is cleared. Added a "👁 camera: <state>" indicator to the status strip
so the coarse perception is visible on-screen.

### Vision capstone P5 (2026-07-05) — demo reproducibility ✅ capstone complete
`Replayer.simulate_vision(waiting|busy|left)` seeds fixed observations so each vision beat
reproduces on cue WITHOUT a live camera (advisory still real Gemma) — matches the replayer's
determinism. Console "Simulate camera" buttons + `POST /vision/simulate`. README gains a
Camera-vision section. +3 tests → 90 green. Verified: simulate → real-Gemma advisory.
**All 5 phases done (#36–#40); epic ready to merge.**

### Vision capstone P4 (2026-07-05) — walk-away change-detection (epic branch)
`WalkedAwayAdvisor` (order-less): the camera saw a customer, now gone, WHILE a flagged order
is still cooking → "re-notify / check on the order." `someone_left` is DEBOUNCED change
detection — the two most-recent obs both absent (not a one-frame flicker) after a present one
— since a single frame can't answer "did they leave?". Own suppression + advise-veto; inert
without the departure pattern OR a flagged cook. Wired into `Replayer.tick`. +5 tests → 87.
Verified live with real Gemma ("Check on the customer's status and expedite the order").

### Vision capstone P3 (2026-07-05) — perception folds into advisories ✅ demoable
Camera perception now produces visible advisories. `Replayer.walk_away` escalates a
BORDERLINE cook (≥0.8 risk, not yet flagged) when a fresh observation shows `people_present`
— filling the "is anyone actually waiting?" gap; `AdvisoryGenerator` snapshot/prompt gains
`customer_waiting`. New `QueueBuildingAdvisor` (order-less, like OpenServer): `busy` camera +
nothing cooking → "start taking orders" nudge, own suppression + advise-veto. Stale/absent
obs → fully inert. +10 tests → 82 green. Verified live: escalated walk-away + queue-building
both fired from real Gemma. **First demoable vision milestone — epic is now merge-worthy.**

### Vision capstone P2 (2026-07-05) — browser capture + opt-in camera toggle (epic branch)
`camera_controller` (Stimulus): opt-in toggle → `getUserMedia` → canvas downscale ~512px →
JPEG → POST `/vision/observations` every ~5s, chained; pulsing "camera on" indicator.
`VisionObservationsController#create` → `VisionClient.observe` → persists coarse obs, prunes,
discards frame. Frame never stored/logged (`:frame` filtered; no blob column). +3 tests → 72.
Verified full round-trip live: browser canvas frame → CSRF fetch → real Gemma → observation
(count 0→1). **`getUserMedia` (camera permission) needs a manual browser smoke-test.**

### Vision capstone P1 (2026-07-05) — VisionClient + fixed-image path (epic/camera-vision)
`VisionClient.observe(path|base64)` — local Gemma 4 vision via Ollama `/api/chat`
(think:false, format:json, `images:[b64]`), coarse contract only (`people_present`,
`queue_level none|light|busy`, `note` — NO counting), safe-default normalize, error → nil
(inert). `VisionObservation` model + migration (uuid, loose shop_id, **no blob column**,
`latest_for`/`fresh?`/`prune!`). Staged fixtures + `rake vision:observe` dev proof.
Verified live: person→present/light, empty→none. +12 tests → 69 green. See #36 / spec.


### Run rush resets learned threshold (2026-07-05)
`Replayer.seed` now also `ShopThreshold.delete_all`, so each demo starts fresh at baseline
sensitivity (×1.5, "alerts after ~7.9m") instead of carrying a raised threshold from a prior
Override. Verified live: 1.65 → 1.5 on Run rush. +1 test → 57 green.

### Browser smoke-test — 2 bugs found + fixed (2026-07-05)
Drove the live demo in a browser (real Gemma/Ollama). Works end-to-end: both advisory types
stream in, queue strip ETA counts down, Override raised "alerts after" 7.9m→8.7m, no console
errors. **Bug 1:** overlapping slow ticks (Run-rush tick + 4s poller) raced the suppression
check → duplicate advisories piled up. Fixed with a Postgres advisory lock in `Replayer.tick`
(overlapping ticks no-op) + the Stimulus poller now chains (schedule next only after the
current finishes). **Bug 2:** Override/Accept on an order-less `open_server` advisory hit
`@advisory.order.shop_id` (nil) → use `@advisory.shop_id`. +1 test → 56 green.

### GemmaClient parse coverage + overnight wrap-up (2026-07-05)
Extracted `GemmaClient.parse_content` (JSON-object extraction from message content, incl.
prose/fence wrapping) and covered it (+3 tests → 55 green) — the last untested load-bearing
piece. **Honest, testable backlog now exhausted:** v1 done, breadth done (open-server, ETA,
baseline, visible learning), reproducibility covered; only no-show stays blocked (needs a
pickup event) and UI wants a human smoke-test. Loop stopping here — see At-a-glance smoke-test.

### Reproducibility integration test (2026-07-04) — hardens the demo path
`replayer_tick_test`: seed → `Replayer.tick` fires both advisory kinds (≥1 walk-away + 1
open-server); a second immediate tick adds nothing (pending + window suppression); same
seed+now flags the same orders (deterministic). Gemma + broadcasts stubbed → offline.
Satisfies DESIGN's "deterministic replay reproduces the same advisory". +3 tests → 52 green.

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
