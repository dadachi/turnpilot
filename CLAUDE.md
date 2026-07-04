# CLAUDE.md — TurnPilot (drop into the submission repo AT KICKOFF)

> This is a **template**. Copy it to the new submission repo's root as `CLAUDE.md` at
> kickoff (Sat 7:00 PM JST) — do not create the submission repo before then.

## What we're building
TurnPilot: a live queue-ops copilot for MyTurnTag shops. A situational model built from a
streaming NFC event feed drives **plain-language advisories** with a one-tap
**Accept / Override** loop, reasoning on **local Gemma (Ollama, offline)**. See design spec.

## Hard rules (violating any = disqualification)
- **NOT a dashboard.** The main feature is the advisory + accept/override loop. Never let a
  charts/metrics page become the centerpiece. ("Dashboard as main feature" is banned.)
- **Reasoning MUST run on Gemma 4, locally/offline** via Ollama (Google Remote track requirement).
  No cloud calls — privacy-first / offline.
- **Gemma 4 is a REASONING model — use Ollama native `POST /api/chat`** (not OpenAI `/v1`) with
  **`think:false`** (else `content` is empty) + **`format:"json"`** (clean JSON). Parse
  `message.content`. No `system` role — instructions go in the user turn. ~2.6s per advisory.
- **New work only, built entirely during the event.** Do NOT copy or import MyTurnTag's
  code (Rails API / iOS / Android). Integrate via the normalized event stream only.
- **Public repo.** Commit frequently with clear messages — the history is our proof the
  work was built during the event. Keep new-vs-preexisting boundaries obvious.
- No banned categories (basic RAG, Streamlit, image analyzer, screeners, coaches, etc.).

## Priorities (judging: Demo 50% · Impact 25% · Creativity 15% · Pitch 10%)
- Get the **v1 walk-away-risk path working end-to-end first**, then breadth.
- Optimize for a working, live, reactive demo over feature count.

## Engineering rules
- Stack: Rails 8.1 + Hotwire (Turbo Streams / Solid Cable), **TailwindCSS v4 (tailwindcss-rails,
  no Node)**, Minitest, local Gemma 4 via Ollama native `/api/chat` (localhost).
- **UUID primary keys on all tables** (generators `primary_key_type: :uuid` + `pgcrypto`).
  MyTurnTag identifiers are stored as plain `uuid` columns — loose references, NOT foreign keys.
- **Colors: Palette 9** (`palette-9.md`) as Tailwind tokens. Light Blue = structure, Pink =
  advisory/alert, Green = Accept, Red = danger, Yellow = warning, Cool Grey = text/neutrals.
- **Keep main always green.** Small verified increments; never leave a half-done refactor.
- Every change: run tests before commit. A broken build is worse than a missing feature.
- **After a PR merges, delete its branch on BOTH remote and local.** Auto-merge's
  `--delete-branch` is unreliable, so verify: `git push origin --delete <branch>` +
  `git branch -D <branch>`, then `git remote prune origin`. Leave only `main`.
- Deterministic event replayer so the demo is reproducible (fixed stream/seed).

## Autonomous overnight loop (Sat 9:30 PM → Sun 7:00 AM JST)
- Work the design-spec acceptance criteria in order; do the ONE path first.
- **Checkpoint to git every cycle.** Append to `STATUS.md` each cycle: what works, what's
  broken, what's next — so triage at 7:00 AM JST takes ~5 minutes.
- Use cheaper models for bulk/mechanical work; reserve the strongest for hard reasoning.
- If blocked or ambiguous, write the question in `STATUS.md` and continue on the next
  independent task rather than guessing on a high-stakes decision.

## Definition of done (per increment)
Tests pass · main green · advisory path reproducible from the replayer · STATUS.md updated.
