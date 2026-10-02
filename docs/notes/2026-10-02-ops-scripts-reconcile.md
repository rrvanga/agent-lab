# 2026-10-02 — ops-script reconcile (issue #28 / PR #29): MERGED

## Outcome
- PR #29 (`chore(scripts): reconcile ops scripts with deployed fixes (#28)`) merged via squash as `9099098`, branch deleted.
- Issue #28 closed, all 4 ACs met.

## What happened
1. **Reconcile** (558c73f): copied deployed `~/.hermes/scripts/{cron_sentinel,morning_context,token_usage_report}.py` into `scripts/`, making the repo canonical. Drift was deployed-ahead-of-repo since 2026-09-14/19/22/26.
2. **Notes** (4eece15): prior run record.
3. **MOA gate re-review** (05f04dc): first gate returned CHANGES-REQUIRED with 5 findings, all fixed:
   - `cron_sentinel.py`: hard failures (doctor couldn't run / jobs.json unreadable) now print FATAL and `return 1` in exactly those two handlers; ordinary findings still exit 0 — prevents nested self-alerting while not silencing real sentinel failures.
   - `morning_context.py` + `token_usage_report.py`: `MODEL_ALIASES` resolved **before** GO_RATES / GO_MODEL_MONTHLY lookups (`default`→deepseek-v4-flash, `agent-main`→deepseek-v4-flash, etc.) — previously alias rows were priced at raw-name flash rates (latent bug) and dropped from per-model caps.
   - `token_usage_report.py`: PER_MODEL_REQ_CAPS corrected (deepseek-v4-flash 63,300 → 13,000; denominator was 4.9x too generous); per-model cost uses alias-first then rate lookup; 5h/7d aggregate queries hoisted out of per-lane loop (2 full-table scans instead of 2×N).
   - Stale GO_MODEL_MONTHLY comment reworded (legacy pool math only).

## Verification (all green)
- `python3 -m py_compile` ×3: OK
- `bash scripts/test-check-ops-drift.sh`: 6 passed, 0 failed
- Alias fix validated against live `~/.hermes/state.db` (session_model_usage): `default` 34 rows / 5.4M tok, `agent-main` 12 rows / 2.4M tok exist → resolution needed & correct.
- Live runs of both reports clean. Note: scripts read `~/.hermes/state.db` (531 MB), NOT `~/.hermes/hermes.db` (0-byte stub — don't be fooled).
- **2nd MOA gate: APPROVE** (exit 0).
- Post-merge deploy repo → `~/.hermes/scripts`; `check-ops-drift.sh` 12/12 OK.
- Deployed copies re-ran clean: deepseek-v4-flash $11.53/30 (38.4% of $30 cap); morning_context 7 sessions/24h.

## Learnings
- **DB stub trap**: `~/.hermes/hermes.db` is a 0-byte stub; the usage scripts read `~/.hermes/state.db`. Verify `.tables` before trusting a DB path.
- **Deploy direction flips during reconcile**: copy deployed→repo (canonical), then the MOA-fix commit makes repo *ahead* of deployed — AC "drift OK" is only achievable **after** merge-then-deploy. Expected; don't gate on drift before deploying.
- **MOA gate mechanics held**: launch early in background (prompt to /tmp, marker line `MOA_GATE_DONE exit=$?`), poll while doing prep work; verdict line at end of output is authoritative.
- Model alias rows (`default`, `agent-main`) are real in the DB and were being mis-priced before this fix — validating against live data caught a latent bug the first gate flagged independently.