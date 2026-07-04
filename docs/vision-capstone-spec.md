# TurnPilot — Camera-Vision Capstone Spec (on-device Gemma perception input)

Working spec for the camera-vision capstone. This adds ONE new **perception input** —
a counter-tablet camera read by **local Gemma 4 vision** — to the existing situational
model. The advisory + Accept/Override loop stays the product; the camera is just an
input it was missing.

## Goal & outcome

Give TurnPilot the one signal MyTurnTag cannot record: **whether a customer is actually
there**. A coarse, on-device camera read ("someone is waiting", "queue building",
"someone just left") folds into the situational model so advisories become
*customer-aware*: a slow-cooking order matters more when someone is visibly standing at
the counter, and a building queue with nothing started is worth a nudge even before any
order is late.

Outcome for the demo: the same advisory loop, but reacting to the physical room —
turn the camera on, a person steps into frame, and a previously-quiet flagged order
escalates to an advisory with "a customer is waiting" in the rationale.

## Why — the honest gap this fills

Per the corrected data model (`docs/DESIGN.md`, memory `myturntag-data-model-reality`):
**MyTurnTag records no customer-join signal.** `idled` tags are pre-created regardless
of any customer (an idled tag may be empty stock on the rack), pulling an NFC tag is not
logged, and `customer_read_at` is customer-controlled. The only reliable events are the
two staff timestamps (`prepared_at`, `completed_at`). So today TurnPilot can see
*cooking*, but it cannot see *waiting* — the very person the walk-away-risk advisory is
about is invisible.

A camera on the counter tablet, read locally by Gemma 4 vision (`gemma4:e4b` is
multimodal — verified in a spike), supplies exactly that missing perception, with zero
change to MyTurnTag and zero cloud dependency. This is not bolted-on breadth; it closes
the model's honest blind spot.

## Non-goals

- **Not an image analyzer.** No image-upload UI, no "describe this photo", no gallery,
  no stored frames. The camera is a background sensor feeding the advisory loop.
- **No head-counting.** The spike showed exact counts are unreliable (Gemma nailed 3
  circles but consistently said 6 for 5). We never display, store, or reason on an exact
  count — only coarse bands.
- **No identification.** No faces, no demographics, no tracking individuals across
  frames, no "regular customer" features. The model is asked only about presence and
  queue pressure.
- **No cloud vision, ever** — no Google Vision API, no hosted multimodal fallback. If
  Ollama is down, the feature degrades to "no perception" (the existing timestamp-only
  behavior), silently.
- No recording, no snapshots for later, no video storage of any kind.

## Guardrails / DQ-avoidance (read first, violating these sinks the entry)

1. **"Image analyzer" is a banned category.** The camera must remain a PERCEPTION INPUT
   to the existing advisory + Accept/Override loop — never the centerpiece, never a
   standalone screen. The console keeps the advisory stream as its main feature; the
   camera surface is a small opt-in toggle + indicator, nothing more.
2. **On-device / offline only.** Vision runs on local Gemma 4 via Ollama's native
   `POST /api/chat` — same edge/privacy thesis as the reasoning path. Any cloud vision
   call breaks the Google Remote track premise.
3. **Privacy by construction.** Frames are processed in memory and discarded; only the
   derived coarse signal is persisted. Camera is opt-in per session with a visible
   "camera on" indicator. See *Privacy & opt-in*.
4. **Main stays green.** `main` is branch-protected — all work lands on
   `epic/camera-vision` (and child branches/PRs), never pushed to `main` directly.
   Small verified increments; tests before every commit.

## Coarse-signal contract

Gemma is asked for a qualitative read, JSON-only. The exact shape (the ONLY thing the
server keeps):

```json
{
  "people_present": true,
  "queue_level": "light",
  "note": "one person standing at the counter"
}
```

| key | type | meaning |
|---|---|---|
| `people_present` | boolean | anyone visible waiting in the counter area |
| `queue_level` | `"none" \| "light" \| "busy"` | coarse pressure band — never a number |
| `note` | short string | one-line human-readable read (shown in advisory rationale only) |

Derived server-side (NOT asked of the model, because single-frame "did someone leave?"
is unanswerable):

- `someone_left` — change detection across consecutive observations:
  `previous.people_present && !current.people_present` (debounced, see P4).

Contract rules:

- Unknown/extra keys are ignored; missing keys degrade to the safe default
  (`people_present: false`, `queue_level: "none"`) — absence of perception must never
  *create* urgency.
- Any parse failure or Gemma error → observation skipped, feature silently inert
  (mirrors `AdvisoryGenerator`'s rescue-and-log posture).
- `queue_level` is clamped to the three bands; anything else maps to `"none"`.

## Architecture

```
Browser (console, opt-in)                    Rails                          Ollama (localhost)
┌─────────────────────────┐   POST /vision/observations   ┌──────────────┐   /api/chat
│ camera_controller.js    │ ────────────────────────────► │ VisionClient │ ──────────────►
│  getUserMedia → canvas  │   { frame: <base64 jpeg> }    │  (mirrors    │   gemma4:e4b
│  downscale ~512px JPEG  │                               │  GemmaClient)│   think:false
│  every ~5s while ON     │                               └──────┬───────┘   format:"json"
│  visible ● REC-style    │                                      │           images:[b64]
│  "camera on" indicator  │                          VisionObservation (coarse signal only;
└─────────────────────────┘                          frame discarded after the call)
                                                              │
                                     Replayer.tick / advisory generation reads the
                                     latest observation → customer-aware advisories
                                     (existing Advisory / ShopThreshold / suppression)
```

- **Browser:** a Stimulus `camera_controller` on the console. Opt-in toggle starts
  `getUserMedia`, draws the video onto a canvas downscaled to ~512px wide, exports JPEG
  (~quality 0.6), POSTs base64 every N seconds (default 5s) while enabled. Chained like
  `replay_controller` (next capture scheduled only after the current POST resolves — a
  warm vision call is ~1.1s but cold is ~7.6s, so fixed intervals would overlap).
  A visible indicator (pulsing dot + "camera on") renders whenever capture is active.
- **Server:** `VisionObservationsController#create` takes the base64 frame, calls
  `VisionClient.observe(frame)`, persists the coarse `VisionObservation`, discards the
  frame, returns 200. No frame ever touches the DB, disk, or logs.
- **`VisionClient`:** mirrors `GemmaClient` — native `POST /api/chat`, `think:false`,
  `format:"json"`, parse `message.content` via the same outermost-`{...}` extraction —
  plus `images: [<base64>]` in the user message. Prompt asks ONLY the coarse questions
  (presence, band, one-line note); it explicitly does not ask for a count. Reuses/shares
  `GemmaClient.parse_content` rather than duplicating it. Env:
  `VISION_MODEL` (default `gemma4:e4b`), same `GEMMA_ENDPOINT`.
- **Situational model:** perception is one more input to `Replayer.tick`-style
  generation, read as "latest observation for this shop, fresh within ~30s":
  - *Urgency modulation:* when a cooking order is near/over threshold AND
    `people_present`, include that in the Gemma advisory snapshot ("a customer is
    visibly waiting") — and allow a borderline order (e.g. ≥ 0.8 walk-away risk) to
    advise when someone is present.
  - *New nudge — `queue_building`:* `queue_level == "busy"` while nothing is cooking
    (`cooking_count == 0`) → shop-level advisory ("customers are lining up but no orders
    have been started"), built exactly like `OpenServerAdvisor` (order-less, own
    suppression window, Gemma advise-veto).
  - *Walk-away change-detection (P4):* `someone_left` while a flagged order is still
    cooking → "the waiting customer may have just walked away — check / re-notify"
    advisory.
  - Stale or absent observations (camera off, Ollama down) → all of the above inert;
    behavior identical to today.
- **Deterministic demo path:** like the replayer, the vision path accepts a fixed
  fixture image (`test/fixtures/files/vision/*.jpg`, staged photos with no real
  customers) via a dev-only param/env, so the full advisory chain reproduces without a
  live camera and tests run offline with `VisionClient` stubbed.

## Data-model changes

One new table, `vision_observations` (UUID PK like everything else):

| column | type | notes |
|---|---|---|
| `shop_id` | `uuid` | loose reference, NOT a foreign key (matches convention) |
| `people_present` | `boolean` | from the contract |
| `queue_level` | `string`/enum | `none \| light \| busy` |
| `note` | `string` | Gemma's one-liner (no PII by prompt design) |
| `observed_at` | `datetime` | capture time |

Explicitly NO image/blob column — the schema itself enforces "frames are never stored".
Observations are ephemeral working state: pruned on `Replayer.seed` (like advisories)
and older rows periodically deleted (retain ≤ 1 hour). `Order`/`Advisory`/
`ShopThreshold` are unchanged; `Advisory.kind` gains `queue_building` (and P4's
walk-away variant reuses `walk_away_risk` with a vision-sourced rationale or a
`walked_away` kind — decided in P4).

## Privacy & opt-in

- **Opt-in, per session:** camera starts OFF; a staff member must tap the toggle. The
  browser's own permission prompt is the second gate. Toggle state is not persisted
  server-side — reload = camera off.
- **Visible indicator:** whenever frames are being captured, the console shows a
  persistent, unambiguous "camera on" indicator next to the toggle.
- **Frames are transient:** processed in memory (request body → Ollama call on
  localhost → discarded). Never written to DB, disk, cache, or logs; never leaves the
  machine (Ollama is localhost — same box).
- **Only the derived signal is kept:** the boolean/band/note above, auto-pruned.
- **No identification:** the prompt asks about presence and queue pressure only. The
  `note` prompt instructs "do not describe individuals' identity or appearance details".
- These points go in the pitch — they're the edge-AI story, not fine print.

## Acceptance criteria (capstone-level)

- A fixture image drives the full chain offline-from-the-camera: fixed image →
  `VisionClient` (real local Gemma) → `VisionObservation` → tick → customer-aware
  advisory in the console. Reproducible, demoable without a live camera.
- With the camera toggle ON in a browser, a person entering the frame changes
  `people_present` within ~2 capture cycles, and a borderline flagged order escalates
  to an advisory citing the waiting customer.
- `queue_building` nudge fires on `busy` + nothing cooking, respects its suppression
  window, and Accept/Override work on it (order-less, like `open_server`).
- Camera OFF / Ollama down / garbage model output → zero behavior change vs today
  (tests assert the inert path).
- No code path stores or logs a frame (test greps/asserts the controller and client).
- Tests cover: contract parsing + clamping, staleness gating, change-detection
  debounce, and each advisory trigger — all with `VisionClient` stubbed (offline).
- Main stays green; STATUS.md updated each increment.

## Risks

- **Model unreliability beyond counting.** Even coarse reads may wobble (lighting,
  angles). Mitigations: three-band contract, safe-default degradation, staleness gate,
  P4 debounce (require 2 consecutive frames to agree before `someone_left`), and the
  Gemma advise-veto already in the loop. If presence itself proves flaky in real
  testing, the demo falls back to the fixture-image path (P1) which is deterministic.
- **Latency stacking.** A vision call (~1.1s warm) + advisory calls share one Ollama.
  Chained capture + the existing chained tick keep calls serialized; capture interval
  (5s) leaves headroom. Watch for cold-load (~7.6s) on the first call — warm the model
  at demo start.
- **DQ perception risk.** A judge glancing at a camera feature may think "image
  analyzer". Mitigation: no frame is ever displayed in the UI (indicator only, no
  preview beyond the moment of enabling), the pitch leads with the advisory loop, and
  the spec/README language consistently says "perception input".
- **`getUserMedia` constraints.** Requires HTTPS or localhost, and a device with a
  camera. Demo runs on localhost (fine); the fixture path covers machines without
  cameras.
- **Scope creep.** This is the capstone, built only after the core loop is solid.
  Each phase is independently shippable; stopping after P3 still demos.

## Phased implementation plan

Each phase = one PR into `epic/camera-vision`, tests green, STATUS.md updated.

### P1 — `VisionClient` + fixed-image path (foundation, no browser)
- `VisionClient.observe(base64_or_path)` — `/api/chat`, `think:false`, `format:"json"`,
  `images:[b64]`; coarse-contract prompt (no counting); shares JSON extraction with
  `GemmaClient`; clamps/defaults per the contract.
- `vision_observations` migration + `VisionObservation` model (bands as enum,
  `latest_for(shop_id)`, `fresh?` staleness check, pruning).
- Fixture images (staged, no real people's identities) + a dev entry point
  (rake task or console one-liner) proving image → observation with real local Gemma.
- Tests: contract parsing, clamping, safe defaults, error → nil (Gemma stubbed).

### P2 — Browser capture + opt-in toggle
- Stimulus `camera_controller`: toggle → `getUserMedia` → ~512px JPEG → chained POST
  every ~5s; visible "camera on" indicator; camera off on disconnect/reload.
- `VisionObservationsController#create`: frame in, `VisionClient` call, observation
  persisted, frame discarded; never logged.
- Dev fixture mode: an env/param makes the endpoint use a fixture image, so the path
  works on camera-less machines.
- Tests: controller (client stubbed) creates observation + never persists the frame;
  bad payloads → 422/no-op.

### P3 — Fold perception into advisory generation
- `Replayer.tick` (or its per-shop hook) reads the fresh latest observation.
- Urgency modulation: `people_present` enters the walk-away snapshot/prompt; borderline
  (≥ 0.8 risk) orders may advise when someone is present.
- New `queue_building` shop-level advisory (busy + `cooking_count == 0`), modeled on
  `OpenServerAdvisor` — suppression window, advise-veto, order-less Accept/Override.
- Stale/absent observation → identical-to-today behavior (asserted).
- Tests: each trigger + the inert path, Gemma and broadcasts stubbed.

### P4 — Walk-away change-detection
- Server-side `someone_left` from consecutive observations, debounced (2 frames agree).
- While a flagged order is still cooking: "customer may have just walked away" advisory
  (kind decided here: reuse vs `walked_away`), with suppression.
- Tests: debounce, trigger, suppression.

### P5 — Demo polish + reproducibility
- Fixture-image replay mode wired into the demo script (deterministic vision beats:
  empty → person waits → person leaves) alongside `synthetic_rush.json`.
- Console copy/indicator polish (Palette 9: camera indicator in advisory pink family;
  toggle in structure blue), model warm-up on demo start.
- STATUS.md + README: perception-input framing, privacy bullets, demo steps.
- Full smoke-test with a live camera + real Gemma; acceptance checklist above signed off.
