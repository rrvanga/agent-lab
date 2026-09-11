# 2026-09-11 Run: Finish PR #23 — ops-scripts-reconcile (MOA gate → merge → close #22)

## Task picked
Complete the ops-script drift reconcile (issue **#22**) to a truthful end state: the 09-09 gate
produced **no verdict** (context-compression timeout, session `20260909_090400_c2d3ad`), so the
09-09 note's "Verdict: APPROVE / PR merged / issue closed" claims were retracted.
This run: fresh MOA gate → merge PR #23 → close issue #22 → truthful notes.

## What changed
- **Truthfulness fix** (`d355d11`, on `feat/ops-scripts-reconcile`):
  - `docs/notes/2026-09-09-run-ops-scripts-reconcile.md` rewritten as an explicit correction
    (three false claims retracted; true 09-09 facts + valid verification results recorded).
  - `docs/notes/2026-09-08-run-ops-scripts-reconcile.md` outcome re-corrected to point at this note.
- **Merged** PR #23 (squash, `--delete-branch`) → commit
  `bb4ac7145290ffa78272b6b6394c3d1de818b71c` on `main` (22 files, +1404/-30).

## MOA gate — two attempts (the failure is the lesson)
- **Attempt 1** (as originally planned): full diff inline, prompt **74,286 bytes**. hermes chat
  auto-compaction triggered; aux compression **timed out** → no message produced
  (`Context compression timed out...`), no verdict. Same failure mode as 09-09 — the full-diff
  inline prompt is the root cause, confirmed twice. (Runner log `/tmp/moa-gate-pr23.log`, session
  `20260911_123421_373eeb`.)
- **Attempt 2**: **tight prompt** (11,110 bytes): full text of the only two new-logic files
  (`scripts/check-ops-drift.sh`, `scripts/test-check-ops-drift.sh`) + diffstat + provenance
  summary of the byte-identical imports. Gate completed.
  **FINAL VERDICT: APPROVE** (aggregator line `FINAL VERDICT: APPROVE`; PII/secret scan clean;
  non-blocking concerns: WARN has no exit-code effect (suggest `--strict` flag later), theoretical
  NUL-in-filename gap, one doc-inventory nit re battery-band-monitor.sh disabled-job status).

## Verification (live)
- `scripts/check-ops-drift.sh` → exit 0, **12/12** cron-referenced scripts present & identical.
- `scripts/test-check-ops-drift.sh` → **6/6** scenarios pass.
- `bash -n` on every `scripts/*.sh`; `py_compile` on every `scripts/*.py` → clean.
- PII scan: no hardcoded credentials; `Authorization: Bearer *** lines are env-var reads.

## Issue #22
Closed with resolution summary (imports in repo = source of truth; drift checker + tests added;
run-note corrections committed).

## Learning / production findings
- **Rule: embed the diff, but keep the prompt tight.** Full-diff inline prompts (>70 KB) force
  hermes chat auto-compaction, whose aux call times out → NO verdict, silently (chat exits 0).
  Embed only genuinely new logic in full; summarize mechanical imports; append diffstat. A
  10-15 KB prompt gates cleanly in ~15 min.
- **Verdict extraction must tolerate `FINAL VERDICT: X` formatting** — the runner's bare
  `^(APPROVE|REQUEST_CHANGES)$` anchor missed the aggregator's `FINAL VERDICT: APPROVE` line
  (runner exited 2 "NO VERDICT" despite an explicit approve; verdict taken from the log). Anchor
  on `FINAL VERDICT:` + bare-line fallback.
- Pre-existing production debt (not introduced by this PR, predates 09-04): deployed copies of
  `local_backup_watchdog.sh`, `llm-watchdog.sh`, `validate-config.sh` send
  `Authorization: Bearer ***` instead of `Bearer $API_KEY` → the opencode-go gateway returns 401
  (real key = 400, i.e. auth passes) → `cloud_healthy()` always false → local_backup_watchdog
  always believes cloud is down. Tracked as follow-up issue.