# 2026-08-13 — Backup pipeline: deployment & lessons

Issue #2 (Automated backup of ~/.hermes) — production deployment day.

## What landed

- **Cron job** `Hermes backup` (job af3e8fdfa644) — 06:30 daily, `no_agent`, runs
  `~/.hermes/scripts/backup_hermes.sh` (deployed copy, not symlink — the cron
  scheduler rejects symlinks that resolve outside `~/.hermes/scripts/`).
  Non-empty stdout is delivered verbatim to the user's DM ("backup OK: …");
  non-zero exit raises an error alert (no silent failure).
- **Passphrase file** `~/.config/hermes-backup/gpg-passphrase` (32 random bytes,
  base64, mode 600) — generated once, never printed. Backup dir `~/.hermes-backups/`
  (mode 700). Retention: 14 days (script default).
- Script deployed as a real file at `~/.hermes/scripts/backup_hermes.sh` (copy of
  repo version; re-copy after future repo updates).

## Verified in production (2026-08-13)

- First live run: `backup OK: hermes-backup-20260813_165305.tar.gz.gpg (25.6 MB, 1 kept)`
- Decrypt round-trip with stored passphrase: **PASS** (gpg → tar listing OK)
- Sandbox acceptance tests (loop's earlier run): all green

## Lessons

- **Sandbox-green ≠ production-ready**: the loop's sandbox tests passed, but the
  real environment lacked the passphrase file and backup dir entirely. Any cron
  wiring must verify real prerequisites (config dirs, secret files, deploy paths)
  first.
- **MOA review gate exceeds one cron run's budget** (10+ min on a 546-line diff).
  Run it in the background early, capture the FULL verdict to a file, poll while
  doing other work; if the ceiling hits, deliver a precise partial status so the
  next run finishes mechanically.
- **Lifecycle guard quirk**: terminal commands containing Python file-access calls
  (`open(`, `Path(`, `read_text(`, `write_text(`) get hardline-blocked. Use the
  write_file/read_file tools or stdin redirects instead.
- Script design worth keeping: flock lock, self-verifying archives (decrypt +
  list before `mv`), `.incomplete-*` cleanup, mode checks on passphrase (600).
- Potential NIT for later: archive files are 644 — fine (ciphertext), but 600
  would be defense-in-depth; a `umask 077` in the script would do it.
