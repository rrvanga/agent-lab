# 2026-10-08 — Go meter: Space Bunny comment pin to verified live state (issue #34, PR #35)

## Summary
Docs pages are **not stable day-to-day or even hour-to-hour**. This run's first
premise — "docs/go reverted to Space Bunny Free, paid row gone" — came from a
single cached 09:00 fetch. The MOA gate's cache-busted re-fetch (~09:35 PT)
disproved it: **docs/go currently lists PAID Space Bunny** (id `space-bunny`,
`zen/go/v1`, $0.15/$0.60/$0.03 per M, $30/mo, 3,130 req/5h) and **docs/zen lists
Space Bunny Free** (id `space-bunny-free`, `zen/v1`) as a free stealth model.
Gate verdict: CHANGES REQUESTED → first patch reverted, comments re-pinned to the
verified state.

## Changes (implemented via `opencode run` one-shot, `-f` spec; comment-only)
1. `space-bunny` (paid) → **LIVE 2026-10-08 Go docs**, comment pins price/cap/endpoint
   (`zen/go/v1`); rates (0.15/0.60/0.03) and caps (30/mo, 3130 req/5h) unchanged.
2. `space-bunny-free` → **free Zen stealth model** (docs/zen id, base `zen/v1` per
   `~/.hermes/config.yaml` routing); $0 rates kept; no Go attribution.
3. `GO_MODEL_MONTHLY` + `PER_MODEL_REQ_CAPS` comments → live 10-08 Go reading, with the
   Zen-free no-cap caveat.
Files: `scripts/token_usage_report.py` (4 lines) + `scripts/morning_context.py` (3 lines).

## Verification
- Original wrong patch: MOA gate rejected with a cache-busted fetch (docs/go + docs/zen)
  + local evidence (`config.yaml:16` routes `space-bunny-free` → `zen/v1`; state.db has a
  `space-bunny-free` usage lane, no `space-bunny` lane). Values in the 10-07 commit were
  already correct — the gate's block was right.
- Corrected patch: `py_compile` both ✓ · `git diff --check` ✓ · `token_usage_report.py`
  runtime exit 0 (Go quota 5h 1.8% / 7d 5.4% / 30d 14.7%) · only 7 comment lines changed.
- Second MOA pass: VERDICT in PR #35 conversation.

## Learnings
- **A single cached snapshot is not truth for the Go meter**: docs/go listed
  "Space Bunny Free" at 09:00 and paid "Space Bunny" at 09:35 — flip-flopping within
  the hour, and the free bunny is a *Zen* model anyway (`config.yaml` routes it to
  `zen/v1`). Before touching rate tables, cross-check with a cache-busted fetch +
  page identity (URL/title) + local config routing. One stale cache nearly shipped a
  wrong-priced meter.
- **The MOA gate earns its keep as the false-premise catcher**: its independent
  re-fetch of the source pages is stronger evidence than the branch's own commit
  narrative. When the gate and the branch disagree about *external* facts, re-verify
  live, don't argue from cache.
- **Keep legacy-row semantics strict**: in these tables `legacy` means "absent from
  the live catalog"; a live row must never be marked legacy because of a stale cache.