# backup.md — Hermes encrypted daily backup

> **SUPERSEDED 2026-09-04** — this custom encrypted layer is retired. Replaced by
> Hermes' built-in `hermes backup -q -l daily` (cron job `daily-hermes-backup`,
> 06:30), which writes consistent snapshots to `~/.hermes/state-snapshots/`
> (restore via in-session `/snapshot restore <id>`). See
> `docs/notes/2026-09-04-backup-retirement.md`. The scripts below remain for
> history — do not re-deploy them.

Crash-safe, encrypted snapshots of the Hermes agent home (`~/.hermes`), with
retention pruning. Implemented as a bash script pair:

| File | Purpose |
|---|---|
| `scripts/backup_hermes.sh` | main backup script (run from cron as a no-agent job) |
| `scripts/restore_hermes.sh` | decrypt / verify / extract helper |

Output lives in `~/.hermes-backups/` as
`hermes-backup-YYYYMMDD_HHMMSS.tar.gz.gpg` (UTC timestamps; the timestamp sorts
lexicographically, which is what makes retention pruning by filename safe).

## Design rationale

### Why `sqlite3 .backup` snapshots for the live databases

`state.db`, `kanban.db` and `verification_evidence.db` are written **live** by
the gateway process while it runs. Taring them directly is unsafe: the gateway
may be mid-transaction, so a plain copy can be torn (a `-wal`/`-shm` file
without its database, a half-written page, a database that fails
`integrity_check` on restore).

Snapshotting with the sqlite online backup API — i.e.
`sqlite3 <db> '.backup <tmp>'` — takes a consistent snapshot that respects
SQLite's locking and WAL mode even while the gateway is writing. The backup
uses a 15s busy timeout (`.timeout 15000`) so a momentarily locked database is
waited on rather than failing the run. Each of the three databases is
snapshotted into a throwaway directory on **real disk** under
`~/.hermes-backups` (not `/tmp`, which may be tmpfs/RAM), that directory is
referenced by tar (the live `*.db` files and their `-wal`/`-shm`/`-journal`
sidecars are excluded), and the whole directory is removed via a
`trap ... EXIT` afterwards. Result: a single, consistent, single-member
tarball.

### Why GPG symmetric encryption

`~/.hermes/.env` and `~/.hermes/auth.json` contain API keys and tokens, so the
backup is a high-value target if it lands on a cold disk, a cloud-synced folder,
or a compromised machine. The tarball is therefore piped straight into gpg
(`tar czf - | gpg --symmetric --cipher-algo AES256`) so that **ciphertext, not
plaintext, is the only thing that ever touches disk**. The plaintext tarball
exists only inside a memory pipe between `tar` and `gpg`. Exclusions
(`hermes-agent/`, `bin/`, `cache/`, images, `*.pyc`, `*.lock`, `gateway.pid`,
`gateway_state.json`, `.hermes_history`, and the live DB files with their
`-wal`/`-shm`/`-journal` sidecars) keep the backup small and free of the git
source checkout and transient caches.

### Why the passphrase lives outside the backup set

The passphrase is stored in `~/.config/hermes-backup/gpg-passphrase` — **not**
under `~/.hermes`, so it is never captured by the backup itself. Otherwise a
compromised backup would ship the key to decrypt it. Because it is deliberately
outside the backup set, a backup restored on a fresh machine can still be
decrypted as long as you re-create (or re-import) the passphrase file there.
The scripts never contain, print, or log the passphrase; they only read the file
at runtime, and the path is overridable via `PASSFILE` (or
`--passphrase-file` on the restore helper).

## One-time setup

1. Install prerequisites (all are Arch standard packages):

   ```
   pacman -S --needed gnupg sqlite tar gzip coreutils
   ```

2. Generate a passphrase file and lock its permissions (the `umask 077` ensures
   the file is created `600` from the start — never world-readable, not even
   transiently):

   ```
   mkdir -p ~/.config/hermes-backup
   (umask 077; openssl rand -base64 32 > ~/.config/hermes-backup/gpg-passphrase)
   chmod 600 ~/.config/hermes-backup/gpg-passphrase
   stat -c %a ~/.config/hermes-backup/gpg-passphrase   # must print 600
   ```

   Both scripts **enforce** mode 600 and refuse to run if the file is more
   permissive than that (they also require it to exist, be non-empty, and be
   readable).

3. **Store a copy in a password manager.** The passphrase deliberately lives
   outside the backup set, so a backup restored on a fresh machine can only be
   decrypted if you can recover the passphrase from elsewhere. Losing the
   passphrase file = losing every backup.

4. Create the backup directory (the script also does this on every run):

   ```
   mkdir -p ~/.hermes-backups && chmod 700 ~/.hermes-backups
   ```

5. Run once by hand to confirm it works:

   ```
   bash scripts/backup_hermes.sh
   # backup OK: hermes-backup-20260812_080000.tar.gz.gpg (62.3 MB, 1 kept)
   ```

## Install the cron job

Symlink the script into the deployed scripts dir (as with the other cron
scripts) and point a no-agent cron entry at it:

```
ln -sf ~/dev/agent-lab/scripts/backup_hermes.sh ~/.hermes/scripts/backup_hermes.sh
```

Example cron line (daily 08:00, stdout delivered verbatim):

```
0 8 * * *  bash ~/.hermes/scripts/backup_hermes.sh
```

A no-agent cron job means stdout is delivered verbatim: **empty stdout means
silent success is *not* how this works — the script prints exactly one summary
line on success** (`backup OK: ...`) and an `ERROR: ...` message plus non-zero
exit on failure. If the script fails, the cron delivery will contain the error
message. Nothing is printed on success beyond that single line.

The same script can be run manually at any time; it is idempotent.

## Retention policy

The 14 most recent backups are kept; older ones are deleted. Because filenames
are `hermes-backup-YYYYMMDD_HHMMSS.tar.gz.gpg`, the timestamp prefix sorts
lexicographically in time order, so a stable filename sort is also a time sort.
Pruning only happens **after** the new backup was created **and** its integrity
was verified (decrypt → `tar -tz` must succeed), so a failed backup never
triggers deletion of older good ones. The count shown in the summary line is the
number of backups remaining after pruning. Set `RETENTION` to override (e.g.
`RETENTION=30 bash scripts/backup_hermes.sh`). Stale `.incomplete-*.gpg`
temporaries older than a day are swept on every run, and a `flock` guard makes
concurrent runs fail loudly instead of racing over the same second.

## Restore procedure

Always restore into a scratch dir first to validate the archive:

```
bash scripts/restore_hermes.sh ~/.hermes-backups/hermes-backup-20260812_080000.tar.gz.gpg
```

With no dest-dir, the script creates a `mktemp -d` scratch dir, decrypts,
verifies with `tar -tz`, extracts (the tree then contains `.hermes/...`), prints
the destination path, and runs `PRAGMA integrity_check` on every database found
in the restored archive to prove the restore worked. Inspect the result before
going any further — the script itself prints `state.db integrity: ok` and the
`Using scratch restore dir: <path>` line; use that exact `<path>` if you want to
poke at the restored files by hand. Don't guess at `/tmp/tmp.*` globs, which can
race other scratch dirs.

A full live restore is **destructive** — it overwrites files in the destination:

```
# 1. STOP the gateway first (restoring under a live process corrupts state):
#    systemctl --user stop hermes-gateway   (or `hermes gateway stop`)
# 2. Extract over ~/.hermes:
bash scripts/restore_hermes.sh ~/.hermes-backups/hermes-backup-20260812_080000.tar.gz.gpg ~/.hermes
# 3. Check the restored db:
sqlite3 ~/.hermes/state.db 'PRAGMA integrity_check;'   # -> ok
# 4. Restart the gateway:
#    systemctl --user start hermes-gateway
```

The script infers the archive root from the archive itself. Because the
archive members carry the `.hermes/` prefix, passing the hermes home itself as
dest-dir (`~/.hermes`, whose basename matches the archive root) puts the script
into **live mode**: it extracts with `--strip-components=1` so `config.yaml`
and `state.db` genuinely overwrite the live files, then asserts that no
`.hermes/.hermes/` nesting occurred and that `config.yaml` landed at live depth.
If you instead pass a *parent* directory (e.g. `~`), the archive root is
preserved and the same result is achieved by extracting `.hermes/` into it.
Anything else (scratch dirs, etc.) keeps the `.hermes/` prefix untouched.

Use `--passphrase-file <file>` (or the `PASSFILE` env var) if your passphrase
file is not at the default location. The restore script writes **only** to the
destination directory it is given; it never issues service-management commands —
you stop/start the gateway yourself.

## Troubleshooting

- **`ERROR: required tool 'gpg' not found`** (or `sqlite3`/`tar`/…): the
  prerequisite is missing. `pacman -S gnupg sqlite tar gzip coreutils`.

- **`ERROR: passphrase file not found: ~/.config/hermes-backup/gpg-passphrase`**:
  the passphrase file was never created, or `PASSFILE` points elsewhere.
  Generate it with the `openssl rand` one-time setup above (and make sure the
  copy in your password manager matches).

- **`ERROR: passphrase file must be mode 600 (got 644): ...`**: the scripts
  refuse to run against a more permissive passphrase file. Re-run the setup
  recipe above (or `chmod 600` the file).

- **`gpg: decryption failed: No secret key` / `Bad session key`**: the passphrase
  file is wrong for this backup. The passphrase is the backup's identity — if it
  doesn't match, the file cannot be decrypted (this is by design).

- **Corrupt / undecryptable backup**: `gpg --batch -d <file> | tar -tz` fails,
  or `tar` reports truncated entries. The backup script refuses to prune anything
  in this situation for the *new* backup. For an *old* backup, treat it as
  unrecoverable unless you have a passphrase copy — restore from the next-newest
  intact archive. If this keeps happening, check disk health and whether the
  backup ran while the disk was full.

- **`tar: ...: Cannot stat: No such file or directory`**: a path in the exclude
  set or the snapshot set did not exist. If `state.db`/`kanban.db`/… was missing
  at snapshot time the script simply skips that database; `No such file` from tar
  usually means a configured exclusion path was expected but a prerequisite was
  never set up — re-check that `~/.hermes` exists and the passphrase file is
  present before running.

- **`ERROR: sqlite .backup failed for <db>`**: SQLite could not snapshot the
  database within the 15s busy timeout (e.g. disk full, permissions, a long-held
  write lock, or a database that is genuinely broken). The backup aborts without
  touching retention. Run
  `sqlite3 ~/.hermes/<db> '.timeout 5000' 'PRAGMA integrity_check;'` to diagnose
  the database.

- **`ERROR: another backup run is in progress`**: a previous backup still holds
  the `~/.hermes-backups/.lock` flock. Wait for it to finish (or remove the lock
  if the process died without releasing it).

- **`WARN: <db> integrity` in the summary** (e.g. `state.db`, `kanban.db`,
  `verification_evidence.db`): the live database failed `PRAGMA integrity_check`
  (with a 5s busy timeout). The backup is still created (a snapshot of the
  current bytes) but the source database may be damaged — investigate the live
  database.
