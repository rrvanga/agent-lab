# 2026-10-01 — Ops-script drift reconcile (issue #28, PR #29)

## Task
`scripts/` (repo canonical) had drifted from deployed `~/.hermes/scripts` for 3 cron-referenced scripts; `check-ops-drift.sh` reported WARN on all three. This run reversed the usual deploy direction: copy the deployed fixes **back** into the repo.

## What was reconciled
1. **cron_sentinel.py** — exit-0-on-findings (deployed 2026-09-14). Non-zero exit from a `no_agent` job poisons the job's own `last_status` → `hermes cron doctor` flags the sentinel's own previous run → next run embeds the nested dump → compounding self-alert (observed 6 levels). Alert via stdout (delivered verbatim for `no_agent` jobs) with exit 0; non-zero reserved for the sentinel's own hard failure.
2. **morning_context.py** — Go pricing overhaul verified 2026-09-19 from live opencode.ai/docs/go table. Material corrections vs repo copy: glm-5.3-flash / qwen3.8-flash ~9–13x too high, longcat-2.0 ~4.7x high, muse-spark* ~5x high, hy4-preview ~6x LOW, DeepSeek undercounted. Adds `DS_PEAK_TIERS` (peak 01:00–04:00 + 06:00–10:00 UTC Mon–Fri → 0.792/0.208 time-weighted blend, since `session_model_usage` keeps only first/last_seen aggregates), `GO_MODEL_MONTHLY` per-model caps (Go is per-model limits now: 20%/5h, 50%/7d, 100%/30d — legacy shared $12/$30/$60 pool retained as continuity line), per-model 30d read-out with nearest-ceiling flag (🔴 ≥80%, ⚠ ≥50%).
3. **token_usage_report.py** — same pricing tables + corrected `PER_MODEL_REQ_CAPS` (deepseek-v4-flash 63,300 → real 13,000; the 4.9x-too-generous denominator made the meter read "plenty of headroom" falsely) + wired-in `per_model_quota_line()` per-lane report.

## Execution
- Staged byte-identical deployed copies at `scripts/_reconcile_src/` (sandbox: opencode must not read outside the repo), briefed OpenCode CLI to copy + verify + not commit.
- OpenCode ran: cp ×3, rm staging dir, `py_compile` PASS, drift tests 6/6 PASS, `check-ops-drift.sh` 11/11 OK, exit 0. Committed nothing.
- I reviewed the full diff by hand (479 lines): 3 files only, +319/−90, no secrets, no mode changes, `check-ops-drift.sh` untouched.
- Commit `558c73f` → push → PR #29 → MOA gate in background → merge → issue update.

## Verification
- `python3 -m py_compile` ×3: PASS
- `bash scripts/test-check-ops-drift.sh`: 6 passed, 0 failed
- `./scripts/check-ops-drift.sh`: OK on cron_sentinel.py, morning_context.py, token_usage_report.py (and all 11 referenced scripts)

## Learnings
- Reverse-direction reconcile is the same risk profile as deploy but with the repo as sink: keep the staged source INSIDE the repo so the coding agent can't read production paths, and keep "do not reformat / pricing is authoritative" in the brief — verified by byte-identical result.
- `git diff main...<branch>` before commit vs after — same content, so the MOA diff file can be generated early even pre-commit (allows gate to overlap commit/push work).
- MOA gate prompt: strict verdict line (`APPROVE` / `CHANGES-REQUIRED: …`) + numbered findings format produces parseable output; tight summary + key hunks instead of full inline diff keeps the 10+-min gate from growing.