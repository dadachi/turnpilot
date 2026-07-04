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
- [x] Situational model: per-order wait + walk-away risk vs baseline (`Order#flagged?`)
- [x] Local Gemma 4 advisory via `GemmaClient` (Ollama /api/chat, think:false, format:json)
- [x] Advisory streams to console via Turbo; Accept/Override buttons render
- [ ] **Override should suppress similar advisories + feed back a learned threshold** (v1 gap)
- [ ] **Real-time accelerated replayer** (currently seed anchors mid-rush; add a ticking clock)
- [x] **Tests** for `Order` math (9) + advisory trigger (4, Gemma+broadcast stubbed, offline)
- [ ] Tighten Gemma prompt so `advise` is a strict boolean (model returned a label)
- [ ] Add a sound/toast on new advisory; a compact live queue strip

## Next breadth (after v1 is solid)
open-a-server advisory · ETA-to-customer · no-show re-notify · baseline from stats.

## Blockers / questions for the human (read first)
- _(none)_

## Cycle log (newest first)
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
