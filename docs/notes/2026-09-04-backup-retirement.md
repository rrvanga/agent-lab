# 2026-09-04 — Backup: custom layer retired, built-in layer live

The custom agent-lab backup pipeline (Issue #2, PR #7) is officially **superseded**
by Hermes' built-in backup tooling. Deployment note (2026-08-13) and design doc
(`docs/backup.md`) are marked accordingly; scripts kept for history.

## Why

The custom layer was built because the built-in tooling had not been evaluated
here at the time — not because it did not exist. Hermes has shipped built-in
backup since April 2026: `hermes backup` + `hermes import` landed 2026-04-11
(upstream `fa7cd44b92`), and `--quick` snapshots (`~/.hermes/state-snapshots/`)
plus the `/snapshot` command landed 2026-04-13 (`381810ad50`) — the same
snapshot system now in daily use. Both the built-in and the custom layer use
SQLite's online backup API for crash-consistent DB snapshots; upstream commit
`d47fe28fc5` later absorbed the custom layer's restore-side lesson (blocker B3,
stale WAL/SHM sidecars).

By 2026-08-28 the built-in CLI was mature here (v0.21.0) and was adopted in
place of the custom layer per this decision.

The custom cron job went dormant after its last archive (2026-08-27), so those
archives were frozen snapshots of August-era state only.

## Decision

**User: "yes switch over to built in"** (approved plan, executed 2026-09-04).

New design:

- cron job `daily-hermes-backup` (`7cbfaba35056`), 06:30 PDT, no-agent,
  `--deliver origin` (per-morning confirmation line to the DM — prevents
  recurrence of the silent-dormancy failure that killed the old job, since
  every morning either prints "ok" or alerts)
- wrapper `~/.hermes/scripts/hermes-backup-quick.sh` → `hermes backup -q -l daily`
- snapshots: `~/.hermes/state-snapshots/<UTCts>-daily/` (labeled dirs)
- retention: wrapper keeps newest 14 daily snapshots; built-in global prune
  (keep=20) handles the rest, skipped if a DB failed
- restore: in-session `/snapshot restore <id>`

## Verification (2026-09-04)

- Manual live run: snapshot `20260905-024242-daily` created (339 MB), exit 0
- Manifest: **14 files**, incl. `.env` / `state.db` / `auth.json`; no failed DBs
- `jobs.json` persistence + scheduler heartbeat confirmed
- Old-layer archives (10 × AES-256 GPG, 2026-08-13 → 08-27, ~668 MB): newest
  decrypt round-trip **PASS** (10,430 members) before disposal
- Old archives + stale `.lock` disposed via XDG trash (reversible, 2026-09-04);
  deployed script `~/.hermes/scripts/backup_hermes.sh` retired to trash the same
  day; `restore_hermes.sh` was **never deployed** on this host and remains
  repo-only, now marked DEPRECATED in-repo; passphrase file
  `~/.config/hermes-backup/gpg-passphrase` **retained** (needed only if trash is
  restored — delete once trash is purged)
- Not touched: `~/.hermes/backups/known-good/` watchdog rotation, local-LLM
  watchdog (`:8081` fallback monitor), 492 MB `pre-update-2026-09-04` zip
  (rollback insurance)

First unattended proof: 2026-09-05 06:30 PDT.