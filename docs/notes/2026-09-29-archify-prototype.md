# Archify prototype — evaluation & adoption decision (issue #26)

**Date:** 2026-09-29 · **Type:** experiment evaluation · **Issue:** #26

## What was evaluated

Prototype of [`tt-a1i/archify`](https://github.com/tt-a1i/archify) (MIT, Node.js,
skill v2.17.0) as an agent skill for *verifiable* architecture diagrams, compared
against the current static `render_architecture.py` pipeline (`assets/architecture.html/png`).

Prototype artifacts under `docs/experiments/archify/`:
- `agent-setup.architecture.json` — typed JSON IR (grid layout, source evidence)
- `agent-setup.architecture.html` — self-contained interactive artifact (817,400 B)
- visual-check PNG screenshots (1440×900 / 2048×1320, light+dark) + contact sheet
- `deliver-receipt.json` + `visual-check.json` — machine receipts (committed)

## Result: validation state

| Gate | Result |
|---|---|
| `validate --quality showcase` | 9/9 checks pass, **0 errors / 0 warnings** |
| Delivery composition metrics | 0 proper crossings, 0 ambiguous corridors, 0 label-route-clearance, 0 desktop-readability, max bends 2, min label-route clearance 6 px, min segment 22 px |
| `deliver` determinism | artifact SHA-256 `c9e76cef…a90ec` — byte-identical to committed HTML |
| Evidence verification | `verified: true` — 3 repo sources resolved to revision `7c8465ee` via `--repo-root` |
| `visual-check` (real Chrome) | status **pass**; containment ok at 1440×900, 1600×1000, 1920×1080, 2048×1320 (light + dark); min projected node text 6.88 px (≥ 6 px floor); dock-stage gap 10.2 px (≥ 10) |
| Visual review | automated browser evidence only (`visualReview: pending`) — no image-capable review in headless run |

## PII / security

Strictly masked: no machine username, hostname, absolute path, provider/API URL,
or account ID in the spec or artifact. Only identifying string is the public
repo URL (`https://github.com/rrvanga/agent-lab`), which the evidence checker
*requires* (must match the local Git remote + revision to verify source links).

## Recommendation

- **ADOPT for the agent-lab poster / architecture artifacts:** interactive HTML
  for review, static PNG for display, deterministic receipts for CI trust.
- **SKIP live pipeline replacement (for now):** swapping the cron `render_architecture.py`
  poster pipeline is a design change requiring user approval — out of scope for
  this experiment run, per the issue.

## Learnings

- Grid `layout.mode: grid` + truthful `fromSide`/`toSide` pairs keeps auto-routing
  clean; the over-authored draft (pos/via/labelAt) produced 29 showcase diagnostics
  — let the router work, correct the sides.
- Source evidence (`/meta/repository`) forces `--repo-root` + matching revision;
  evidence is verified against the real checkout, making claims auditable.
- `deliver` is deterministic and atomic (byte-identical HTML on re-run), so a
  committed artifact + receipt is genuinely reproducible — stronger than the
  static pipeline's "rendered and eyeballed" artifact.
- Start the MOA review gate in the background early; the full gate + fix loop can
  exceed one cron run's iteration budget (see 2026-09-11 run note).