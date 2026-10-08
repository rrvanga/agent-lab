# 2026-10-08 — Go meter: Space Bunny reconcile to live catalog (issue #34, PR #35)

## Summary
The OpenCode Go catalog **flip-flopped** vs the 10-07 snapshot (issue #32): the
live page fetched 2026-10-08 lists **only "Space Bunny Free"** (endpoint
`space-bunny-free`, Free, Unlimited, limited-time promo) — the **paid
`space-bunny` row verified 10-07 is NOT on today's page**. Reconcile = comment-only
flip in both meter copies: free row marked LIVE, paid row marked legacy.

## Changes (implemented via `opencode run` ×2, one-shot, `-f` spec file)
1. `space-bunny-free` → **LIVE 2026-10-08** (limited-time FREE promo; endpoint
   `space-bunny-free`, Free/Unlimited); its rates (0.0 ×4) were already correct.
2. `space-bunny` (paid, 10-07) → **legacy**: paid row from 2026-10-07 docs, NOT on
   live catalog 2026-10-08 (page reverted to free promo); kept for historical rows
   — mirrors existing `grok-4.5` / `deepseek-flash` legacy convention.
3. `GO_MODEL_MONTHLY` + `PER_MODEL_REQ_CAPS` entries → legacy 10-07 comments, caps
   preserved (3130 req/5h, $30/mo).
Files: `scripts/token_usage_report.py` (4 comment lines) + `scripts/morning_context.py`
(3 comment lines). Zero numeric/logic changes.

## Verification
- `py_compile` both scripts ✓ · `git diff --check` ✓
- `token_usage_report.py` runtime exit 0 — Go quota 5h 1.8% / 7d 5.4% / 30d 14.7%.
- state.db lanes: real usage only under `space-bunny-free` (1 msg, tiny → $0 correct).
- MOA gate: VERDICT via `hermes chat -Q -q … -m moa:default` (see PR #35 conversation).

## Learnings
- **The Go catalog page flip-flops between days**: Space Bunny was free (≤10-06),
  paid on 10-07, free again 10-08. Always verify against today's live/cached page —
  a prior commit's catalog state is not authoritative, and per-day comments must
  carry the snapshot date so flips are recognizable.
- **`rm` is lifecycle-guarded in cron mode** — the stale-tmp cleanup lesson from
  08-13 can't be run as `rm -f`; use unique per-run `/tmp` paths (e.g.
  `moa_review_issue34.*`) instead, which sidesteps both the guard and stale
  file collisions.
- **`opencode run` arg order matters**: message positional FIRST, `-f <spec>` after;
  "File not found: <message>" means the parser took the positional as a path
  (option-before-positional + trailing message failed in 1.18.19).