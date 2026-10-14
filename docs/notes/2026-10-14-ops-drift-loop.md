# Closing the ops-drift loop: actionable exit code + explicit reconcile mode (issue #38)

**Date:** 2026-10-14
**Scope:** `scripts/check-ops-drift.sh`, `scripts/test-check-ops-drift.sh`, `scripts/morning_context.py`, `scripts/token_usage_report.py`, `docs/ARCHITECTURE.md`

## What happened

Ops-script reconciliation between the canonical repo `scripts/` and the deployed
`~/.hermes/scripts/` has now been the selected daily-loop task four times (#22 on 2026-09-07,
#28, #36/#37 on 2026-10-13, and again today). Each recurrence had the same shape: a live
writer (the Go adaptive monitor's run, or a manual live edit) changed **only** the deployed
copy, and the repo fell behind by a `GO_RATES` row or two. The recurrence itself is the bug —
`check-ops-drift.sh` detected the drift every time but could not be acted on without manual
`diff`/`cp` work, and its WARN path had **no exit-code effect** (rc stayed 0), so nothing
automated could notice.

Today's instigating drift: the deployed copies held two `GO_RATES` rows absent from the repo,
inserted after the `claude-haiku-5-5` row (repo `morning_context.py:60`,
`token_usage_report.py:36`):

- `'gemini-4-argon-contributor': (0.10, 0.20, 0.002, 0.0)`
- `'ling-3.1-flash-free': (0.0, 0.0, 0.0, 0.0)`

Both ids were checked against the live catalogs before import: `gemini-4-argon` (free,
`zen/v1`) and `gemini-4-argon-contributor` (paid, `zen/go/v1`) exist; **no `ling-*` id exists
on either endpoint** — the row is deliberately retained as legacy so historical usage rows
still price correctly.

## Change

Implemented via `opencode` (spec inlined with `opencode run "$(cat spec)"`), reviewed by hand:

1. **Part A — parity:** the two deployed-only rows were imported into the repo, byte-exact, so
   `check-ops-drift.sh` reports `OK` for both files (`cmp`-identical to the deployed copies).
2. **Part B — make drift actionable:**
   - content drift now exits **3** (was 0), `--help` exists and prints the exit-code table,
     bad usage exits **64**;
   - each `WARN:` line now prints the two exact repair commands;
   - `--reconcile --toward=repo|deployed [--apply]` plans by default (dry run, `PLAN:` lines)
     and only copies when `--apply` is given, then rescans and reports the real rc;
   - guard rails: `--toward` is mandatory in reconcile mode, `--apply` without `--reconcile`
     is rejected, and reconcile refuses empty or `/`-resolving directories.
   - `REPO_SCRIPTS`/`HERMES_SCRIPTS` now use `${VAR-default}` instead of `${VAR:-default}` so an
     explicitly-empty env var (used by the test harness) is honoured rather than silently
     replaced.

## Verification

- `bash scripts/test-check-ops-drift.sh` → **12 passed, 0 failed** (added scenarios for
  `--help`, exit 3, usage error 64 both directions, dry-run no-op, apply both directions,
  no-drift reconcile, missing jobs.json→2).
- `bash scripts/check-ops-drift.sh` → rc **0**, zero WARNs (both `GO_RATES` files `OK`).
- `python3 -m py_compile scripts/morning_context.py scripts/token_usage_report.py` → clean.
- No caller outside the repo depends on the old exit-code contract (grep over
  `~/.hermes/scripts/` and `~/.hermes/cron/jobs.json` found no `check-ops-drift` reference), so
  introducing exit 3 is safe; the scripts themselves are not cron-referenced.

## Lessons

1. **A detector that cannot be acted on is toil.** The drift check was correct for months and
   the same reconcile task kept being selected, because detection had no exit-code signal and
   no one-command repair. When the same chore recurs, automate the repair path — not just the
   observation.
2. **Raise the exit code, but check the callers first.** Changing `0`→`3` for a
   previously-silent warning is a breaking interface change; grep every caller (including
   `jobs.json` `script`/`monitor_script` values) before shipping it.
3. **Dry-run by default, direction mandatory.** A reconcile tool that guesses the direction
   silently corrupts whichever side is wrong. `--toward=` required + `--apply` opt-in + copy
   guard rails keeps the one destructive operation explicit. Direction must follow verified
   truth (this time deployed→repo was correct for the rate rows).
4. **`${VAR:-default}` vs `${VAR-default}` is a testability decision.** The `:-` form makes it
   impossible to test the "empty directory" branch via env override; switching to `-` was
   required for the new guard-rail scenarios.
5. **`opencode` respects `/tmp` permissions strictly.** At the end of the run it tried to clean
   up its own `/tmp/ops-drift-live.out` and was auto-rejected (`permission requested:
   external_directory (/tmp/*); auto-rejecting`) — the task itself had already completed
   (rc 0), so a trailing permission rejection in the log is not a failure.
