# 2026-09-08 Run — Ops-script drift reconciliation (issue #22)

## Outcome (CORRECTED 2026-09-09, re-corrected 2026-09-11)
- PR #23 was **NOT merged on 2026-09-08** — the original note overclaimed. Actual state: branch `feat/ops-scripts-reconcile` (commit `25e093e`) pushed, PR #23 opened 16:03Z, MOA-feedback edits (EOF newlines, PII scrub, doc accuracy) made but **uncommitted** when the run ended. Main never received the feature; issue #22 stayed open.
- 2026-09-09 run: polish edits committed (`5b42d29`), gate re-run but produced **no verdict** (context-compression timeout), so **no merge and no issue close happened** — the 09-09 run note originally claimed otherwise and was itself corrected 2026-09-11. PR #23 remained OPEN; issue #22 remained OPEN. Completion handled on 2026-09-11 (see `2026-09-11-run-finish-pr23.md`).
- Content of the PR: 14 deployed cron/ops scripts imported from `~/.hermes/scripts/` into `scripts/`, PII-templated, plus `check-ops-drift.sh` drift checker + `test-check-ops-drift.sh` harness (6 cases).

## Verification before merge
- 12/12 cron-referenced scripts present and byte-identical (`cmp -s`) on repo + deploy side; drift checker exit 0.
- Test harness: 6 passed / 0 failed (missing-from-repo → ERROR/1; missing-from-HERMES → ERROR/1; content-diff → WARN/0; `--quiet`; missing jobs.json → exit 2).
- PII grep over `scripts/`: clean. `bash -n` all .sh OK; `py_compile` all .py OK.
- Gate diff: 65,528 bytes (largest new files: token_usage_report.py +270, thermal_watch.py +162).

## Lessons
- PII templating for public repo: `/home/<user>` → `$HOME` / `os.path.expanduser("~")`; verify with grep before commit, never trust the assistant's memory.
- `check-ops-drift.sh` is now the sync canary: deploy = `cp scripts/<name>.sh ~/.hermes/scripts/`, then re-run checker to confirm OK. A WARN means one side drifted — reconcile via the repo, never by editing `~/.hermes/scripts/` directly.
- MOA gate on a 65KB diff: reference models take 20–30 min with visible context-compaction spinner; the wrapper exits early — verify the child with `pgrep -f "hermes chat"` before assuming failure.
- Drift check stays manual/local: CI cannot see `~/.hermes/cron/jobs.json` without a fixture (backlog: GitHub Actions drift check with jobs.json fixture).

## Follow-ups (open tech debt)
- Import/document local-only scripts: `adaptive_monitor.py`, `battery-band-monitor.sh`, `boot_local_gemma.sh`, `bridge_poll.sh`, `dgpu-runtime-pm.sh`, `dgpu-runtime-pm-install.sh`, `go-ping.sh`, `go_probe.py`, `kanban-check.sh`, `sleuth_pending.sh`, `skills_vault_scrub.py`.
- Optional CI drift-check job with jobs.json fixture.