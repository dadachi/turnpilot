# STATUS — TurnPilot (drop into the submission repo root at kickoff)

> The overnight loop appends to this every cycle. Keep it short and current so a
> human can triage in ~5 minutes at 7:00 AM JST. Newest cycle on top.

## At-a-glance (update every cycle)
- **Build health:** tests ⬜ pass / ⬜ fail · main ⬜ green · local Gemma (Ollama) ⬜ reachable
- **v1 walk-away-risk path:** ⬜ not started / ⬜ partial / ⬜ working end-to-end
- **Demo replayable from `synthetic_rush.json`:** ⬜ yes / ⬜ no

## v1 acceptance checklist (the ONE path — do this first)
- [ ] Rails app boots; Postgres up; UUID PKs; Tailwind (Palette 9) wired
- [ ] Event replayer streams `joined/prepared/customer_read/completed` into the app
- [ ] Situational model computes per-order wait + walk-away risk vs baseline
- [ ] Local Gemma (Ollama) call returns a parseable advisory (see spike)
- [ ] Advisory streams to the operator console via Turbo (chime + card)
- [ ] Accept / Override both work; Override suppresses + is logged + feeds back
- [ ] Tests cover the model math + the advisory trigger
- [ ] Demo is reproducible from the fixed replay

## Blockers / questions for the human (read first at wake-up)
- _(loop writes anything ambiguous or high-stakes here instead of guessing)_

## Cycle log (newest first)
### Cycle N — <what changed, what works now, what's next> — commit <sha>
