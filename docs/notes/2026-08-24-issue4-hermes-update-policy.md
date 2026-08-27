# 2026-08-24 — Issue #4: Hermes update policy

## What & why
Defined, tested update path for the hermes-agent install. The install is a **git source checkout** on rolling Arch, so "update" = git pull + dependency reinstall, driven by `hermes update` — not a package-manager upgrade. Issue requested: document the git-pull + restart procedure, test on a non-critical day, keep gateway-restart constraints (lifecycle guard) in mind.

## What changed
- New `docs/UPDATE.md` (226 lines, via OpenCode CLI on `feat/update-policy`):
  - Install layout + update policy (maintenance window, non-critical day, no live-agent dependence)
  - Pre-flight: `hermes update --check` dry-run, known-good backup freshness, clean git state
  - Manual update procedure (user-run, not agent-run — lifecycle guard blocks restart patterns)
  - Gateway constraint: systemd **user** service; restart kills child agent processes (kanban workers)
  - Rollback path: checkout previous SHA → venv pip reinstall → known-good config restore → gateway restart → verify
  - Troubleshooting + backup/rollback cross-references

## Acceptance gates (issue #4)
1. `docs/UPDATE.md` exists — ✅ (committed e1c50c6)
2. Dry-run update verified — ✅ live 2026-08-24: `hermes update --check` → "Update available: 808 commits behind origin/main."
3. Rollback path documented — ✅ (git SHA + known-good + restart)

## PR / review
- PR #14 — review gate: MOA verdict pending → merged via squash if APPROVE.

## Learnings
- **Cron terminal stdout is collapsed** ("N lines output") — verify facts by writing stdout to files, then `read_file`, or grep short substrings (short outputs do come through).
- **Session cwd persists across terminal calls** — a `cd ~/.hermes/hermes-agent` earlier made later `gh issue list` hit the UPSTREAM repo, not agent-lab. Always `gh ... -R rrvanga/agent-lab` or `git -C <repo>`.
- **Compaction handoff mislabeled issue mapping** — re-list issues in the target repo before selecting; don't trust a stale snapshot.
- `hermes update --check` is the safe dry-run (no restart, no write); the real `hermes update` restarts the gateway and is auto-flagged by the approval layer.
- Known-good config lives at `~/.hermes/backups/known-good/` (config.yaml + .env, mode 600), refreshed by the llm-watchdog 5-min timer on config changes.
- Gateway unit facts worth remembering: `ExecReload=kill -USR1 $MAINPID` is a graceful reload; a code update needs a full restart since the interpreter/venv changed.

## Refs
- `docs/backup.md` (style model + restore procedure), `docs/DAILY_LOOP.md`, issue #4, PR #14
- Research watch (AI developments, 2026-08-24): `akitaonrails/ai-memory` (Rust; long-term memory handoff across agent CLIs — relevant to cross-agent memory) and `apache/maka` (Incubating; local-first agent workspace with append-only activity log — relevant to agent observability). Both noted for future evaluation, not acted on today.