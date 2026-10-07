# Daily-loop 2026-10-06 — Go meter re-verification + model-routing watch

**Issue:** #30 · **Branch:** `2026-10-06-go-meter-routing-watch` · **PR:** (see Git history)

## Research signal (HN over GitHub trending)
Mistral Large 4 ("le Chonk") launched **2026-10-06** (mistral.ai/news/mistral-large-4/):
1T-param multimodal MoE, ~49B active, **$1.36 in / $4.18 out per M tokens**, open weights
expected end of month. Also surfaced: OpenAI Decisions API, EmbeddingGemma 2,
Reflection Beam 501B — none routable through the Go provider yet.

## Verified: ML4 is NOT in the OpenCode Go catalog
Live `https://opencode.ai/docs/go` (fetched 2026-10-06): **30 models, zero Mistral**.
→ Wiring ML4 into the meter is deferred until it appears on the Go catalog (gate:
search the live docs page for `mistral`; pricing tuple + req/5h needed before any
meter/routing change). Coincidentally cheaper on input than both review refs:

| model | in $/M | out $/M | req/5h | monthly |
|---|---|---|---|---|
| ML4 (not on Go) | 1.36 | 4.18 | — | — |
| deepseek-v4-pro (blend) | 0.7975 | 2.3925 | 1,050 | $15 |
| glm-5.2 | 1.40 | 4.40 | 880 | $60 |
| qwen3.8-max | 2.00 | 6.00 | 160 | $15 |

→ Routing recommendation stands: **deepseek-v4-flash for bulk/default, deepseek-v4-pro
for the MOA review reference tier; no change until an actual limit signal or a catalog
entry for ML4.** Meter tables re-verified 1:1 against live docs for every shared model —
Sept-19 tables were still accurate.

## Changes (implemented via `opencode run` ×2, one-shot, `-f` context spec)
1. **`gpt-6-luna: 4230` added to `PER_MODEL_REQ_CAPS`** — was missing, so its request
   burn was silently skipped by `req_quota_line()` (`if not cap: continue`). Live:
   4,230 req/5h, $15/mo.
2. **Context-tier prices documented as comments** (meter still bills the ≤threshold
   tuple; >threshold tiers noted for humans + future tier logic):
   qwen3.7-plus >256K (1.20/4.80/0.12/1.50); grok-4.6/4.7 >200K (4.00/12.00/1.00);
   gpt-5.6-luna >272K (0.40/1.80/0.04/0.50); gpt-6-luna both tiers.
3. **Stale DeepSeek V4.1 Flash promo comment corrected** — "promo ends 09-20 → $15"
   was wrong: live still **$60/mo / 26,000 req/5h** (promo extended). The 07:30 report
   was mis-pricing that model at the $15 cap.
4. **Go Plus plan noted** ($40/mo, higher per-model limits; meter tracks base Go $10/mo).
5. **Legacy catalog entries marked, not deleted** (`glm-5.1`, `minimax-m2.5`,
   `qwen3.7-max`, `qwen3.6-plus`, `deepseek-flash` GUESS, `grok-4.5` GUESS) — kept for
   historical DB rows; comments flag them absent from the 2026-10-06 catalog.

## Verification
- `python -m py_compile` both scripts ✓ · `git diff --check` ✓
- Runtime: `token_usage_report.py` + `morning_context.py` both exit 0; per-model line
  now prices deepseek-v4.1-flash at its real $60 cap ($0.39/60) — pre-fix it read $15.

## Learnings
- **opencode `run` one-shot + `-f <spec>` works reliably for table/comment maintenance**;
  a follow-up micro-fix (misplaced legacy comment) was also routed through `opencode run`
  rather than hand-editing — keep the "no hand-written code" rule even for comment fixes.
- **Comment placement matters in diff review**: a "legacy" tag on a line with a live
  model misleads future readers; per-token comments beat line-level ones in dense dicts.
- **Live docs page (SPA) renders where raw `.mdx` 404s**: canonical-source cross-check
  `raw.githubusercontent.com/.../docs/go.mdx` failed (14-byte 404 body) — use the
  rendered page cache as authoritative.
- **A model absent from the meter's per-model caps is invisible in the 07:30 report**
  (silent skip) — the gpt-6-luna gap meant its spend/requests never surfaced; sweep
  PER_MODEL_REQ_CAPS vs the live "Estimated requests" table each verification pass.