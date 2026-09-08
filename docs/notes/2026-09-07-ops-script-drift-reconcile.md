# 2026-09-07 — Ops-script drift reconciliation (issue #22)

## Problem
The README/ARCHITECTURE claim the repo is the source of truth for ops scripts, but the deployed
`~/.hermes/scripts/` had silently diverged: 13 cron-referenced or doc-referenced scripts existed
only on disk (some had grown substantial features — token_usage_report.py 10.9 KB, watchdog logic),
while ARCHITECTURE.md's inventory was frozen at 2026-08-11. Cron reads bare filenames from
`~/.hermes/scripts/` only, so repo drift was invisible until something edited a deployed script
and lost it.

## What changed
- Imported 13 scripts into `scripts/` with PII templating (public repo): hardcoded `/home/<user>`
  paths → `$HOME` / `os.path.expanduser("~")`; no behavior changes.
- Added `scripts/check-ops-drift.sh`: parses `~/.hermes/cron/jobs.json` (`"script"` keys), errors
  when a cron-referenced script is missing from repo or deploy side, warns on content drift,
  lists repo-only/local-only files. Environment-overridable for tests.
- Added `scripts/test-check-ops-drift.sh`: fake HERMES_HOME fixture harness (pattern:
  test-nightly-shutdown.sh).
- Refreshed docs/ARCHITECTURE.md (2026-09-07 state, full 20-job roster) and README.

## Lessons
- **opencode CLI permission layer auto-rejects `~/.hermes/scripts/*` reads** (external directory).
  To let OpenCode work on deployed files, stage copies inside the repo (`scripts/_staging/`) and
  have it delete the staging dir when done. Do not use `-f` to attach a prompt file from /tmp —
  the message positional is also treated as a file path and `external_directory (/tmp/*)` is
  auto-rejected; keep prompts in-repo.
- **Cron script lifecycle is now: edit in repo → deploy copy → run check-ops-drift.sh.**
  A content-diff WARN means one side drifted — reconcile via the repo, never by editing
  `~/.hermes/scripts/` directly and forgetting to port back.
- Local-only scripts that aren't cron-referenced (adaptive_monitor, dgpu-runtime-pm, bridge_poll,
  kanban-check, skills_vault_scrub, sleuth_pending, battery-band-monitor, go-ping) remain
  undocumented — next pass should import or explicitly document them.
- ARCHITECTURE.md's "known tech debt" list had gone fully stale (all 4 items resolved); the drift
  checker + this refresh is the new maintenance loop.

## Follow-ups (backlog)
- Import/document the remaining local-only scripts (§7 of ARCHITECTURE.md).
- GitHub Actions cron (optional): run check-ops-drift.sh in CI won't see the live jobs.json —
  needs a fixture; currently drift checking is a manual/local step (daily-loop or cron_sentinel-style job).