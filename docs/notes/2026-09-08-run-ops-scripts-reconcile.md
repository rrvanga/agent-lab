# 2026-09-08 Run — Ops-script drift reconciliation (issue #22)

## Outcome
- PR #23 merged (squash, commit `25e093e`): 14 deployed cron/ops scripts imported from `~/.hermes/scripts/` into `scripts/`, PII-templated, plus `check-ops-drift.sh` drift checker + `test-check-ops-drift.sh` harness (6 cases).
- Issue #22 closed. Verdict: MOA gate APPROVE (deepseek-v4-pro + glm-5.2 refs → qwen3.8-max aggregator).

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