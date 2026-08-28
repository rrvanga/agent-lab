# UPDATE.md — Hermes update policy

Hermes runs from a **git source checkout** (`~/.hermes/hermes-agent`) on a
rolling Arch host, so "update" is not a package upgrade but a `git pull` plus a
dependency reinstall, driven by the built-in `hermes update` command. This
document is the defined, tested path for that update: pre-flight checks, the
manual update in a maintenance window, post-update verification, rollback, and
troubleshooting. It also states the one constraint that shapes everything else:
an agent session **cannot** run this itself (the lifecycle guard), so the update
is always a human, manual action.

## How the install is managed

- **Source checkout**: `~/.hermes/hermes-agent`, branch `main` tracking
  `origin/main` (`origin` = `git@github.com:NousResearch/hermes-agent.git`,
  SSH). `hermes --version` reports the install method as git.
- **Version line** (captured 2026-08-24):
  `Hermes Agent v0.20.4 (2026.8.18) · upstream 057dcdf2 · local 8794e5a2 (+22268 carried commits)`
  — Python 3.11.15, OpenAI SDK 2.24.0, install dir `~/.hermes/hermes-agent`.
  (Line format changed in v0.20.6, updated 2026-08-27: the `· local <sha>
  (+N carried commits)` field is no longer printed — the line now ends at
  `· upstream <sha>`, e.g. `Hermes Agent v0.20.6 (2026.8.27) · upstream 99c3cad8`.)
- **Virtualenv**: `~/.hermes/hermes-agent/venv` (owns `bin/pip`,
  `bin/python3.11`).
- **`hermes update`** is the update driver. Verbatim purpose: *"Pull the latest
  changes from git and reinstall dependencies"*. Relevant flags:
  `--check` (report only, install nothing), `--backup` / `--no-backup`
  (pre-update backup override; `updates.pre_update_backup` is the default),
  `--yes` (assume yes on config-migration / stash-restore prompts — **API-key
  entry is skipped**, run `hermes config migrate` afterwards if keys were
  dropped), `--keep-stash` (keep changes stashed instead of re-applying them;
  used by the desktop updater), `--branch NAME` (update a branch other than
  main). `--force` / `--force-venv` are Windows-only and irrelevant here.
- **Gateway**: systemd **user** service `hermes-gateway.service` (unit at
  `~/.config/systemd/user/hermes-gateway.service`, enabled). `ExecStart` =
  `~/.hermes/hermes-agent/venv/bin/python -m hermes_cli.main gateway run`,
  `WorkingDirectory=~/.hermes`, `HERMES_HOME=~/.hermes`; `Restart=always`,
  `KillMode=mixed`, `KillSignal=SIGTERM`, `TimeoutStopSec=60`,
  `ExecReload=/bin/kill -USR1 $MAINPID`, `ExecStopPost` runs
  `gateway.cgroup_cleanup`. The gateway hosts messaging integrations
  (e.g. Telegram) **and** spawns child agent processes (e.g. kanban workers); a
  full restart kills those children. `systemctl --user reload` only sends USR1
  (graceful reload) — a code update needs a full **restart**, because the venv
  and code have changed.

### The lifecycle guard

Hermes hardline-blocks agent-issued terminal commands whose text matches
restart/recovery patterns. Consequence: an agent session **cannot** perform the
real update + restart — the user must run it in a maintenance window. The
procedure below is therefore always run by a human, manually.

## Update policy

- Run updates in a **maintenance window**: a non-critical day, with no live
  sessions or cron jobs depending on the gateway.
- The user runs the update manually (see Performing the update); agents cannot
  self-update.
- Cadence: weekly, or when a fix is needed — not every commit. If updates are
  skipped for a while, the dry-run keeps printing `Update available: N commits
  behind`; that is expected on a rolling setup, informational rather than an
  error.

## Pre-flight checklist

1. Dry-run and interpret the output:

   ```
   hermes update --check
   → Fetching from origin...
   ⚕ Update available: 1404 commits behind origin/main.
     Run 'hermes update' to install.
   ```

   (On 2026-08-26 the checkout was 1404 commits behind; on 2026-08-28, after
   the 08-27 update to v0.20.6, it was 121 behind — the count varies as
   upstream moves.) `→ Fetching...` shows the remote is reachable; the `⚕`
   line is the real answer. Nothing upstream worth taking? Defer — see policy
   above.

2. Verify the known-good config backup is present and fresh:

   ```
   ls -la ~/.hermes/backups/known-good/
   ```

   Expect `config.yaml` and `.env`, both mode `600`. The `llm-watchdog` timer
   refreshes them every 5 min on config changes, so they should be recent.

3. Verify the working tree is clean, and record the current SHA — **the
   rollback target**, write it down:

   ```
   git -C ~/.hermes/hermes-agent status --short     # must print nothing
   git -C ~/.hermes/hermes-agent rev-parse HEAD     # write this down
   ```

   If `status --short` prints anything, stop — see Troubleshooting.

4. Optional full state backup before updating:

   ```
   bash scripts/backup_hermes.sh
   # backup OK: hermes-backup-20260827_045336.tar.gz.gpg (216.8 MB, 10 kept)
   ```

   The encrypted archive lives in `~/.hermes-backups/` and excludes the git
   checkout and caches; full restore procedure is in `docs/backup.md`. (The
   timestamp is UTC; size and kept-count vary per run.)

## Performing the update

Run manually, from anywhere, in the maintenance window:

```
hermes update --backup --yes
```

The tool pulls from origin, stashes local changes, reinstalls dependencies, and
restarts what it needs to. `--backup` forces a full pre-update backup (quick
state snapshot + `HERMES_HOME` zip) for this run; `--yes` assumes yes on the
config-migration and stash-restore prompts.

Notes:

- `--yes` **skips API-key entry**. If keys were dropped, re-enter them
  afterwards:

  ```
  hermes config migrate
  ```

- `--keep-stash` means local changes are *not* re-applied after the update
  (they remain stashed so the update could proceed; the desktop updater uses
  this). For a normal manual update, let the stash be restored.

## Post-update verification

1. New version line:

   ```
   hermes --version
   ```

   Expect a newer build date and `· upstream <sha>` than the captured version
   line above (the `· local <sha>` field was dropped from the line in v0.20.6).

2. Gateway is running:

   ```
   systemctl --user status hermes-gateway
   ```

   Expect `active (running)` and a recent start time.

3. Real integration round-trip: send one Telegram DM to the gateway and confirm
   the reply. This proves the messaging path survived the restart.

4. Timers still scheduled:

   ```
   systemctl --user list-timers
   ```

   Expect the usual timers (e.g. `llm-watchdog` at 5-minute cadence).

## Rollback path

If the update broke something, in this order:

1. Restore the code to the recorded pre-update SHA:

   ```
   git -C ~/.hermes/hermes-agent checkout <recorded-pre-update-SHA>
   ```

2. Reinstall dependencies for the restored code:

   ```
   ~/.hermes/hermes-agent/venv/bin/pip install -e ~/.hermes/hermes-agent
   ```

3. If config is the problem, restore just the config from known-good:

   ```
   cp ~/.hermes/backups/known-good/config.yaml ~/.hermes/config.yaml
   cp ~/.hermes/backups/known-good/.env ~/.hermes/.env
   chmod 600 ~/.hermes/config.yaml ~/.hermes/.env
   ```

   For a full state restore instead, follow the `docs/backup.md` restore
   procedure: STOP the gateway first, extract, run `PRAGMA integrity_check`,
   then start.

4. Restart the gateway:

   ```
   systemctl --user restart hermes-gateway
   ```

5. Verify: `hermes --version` shows the old build, the gateway is
   `active (running)`, and a Telegram DM round-trip works.

6. Record what happened in `docs/notes/` and on the issue.

## Troubleshooting

- **`✗ Failed to fetch updates from origin.`** (SSH/network): the remote was
  unreachable. The same code path prints the diagnosis variants
  `✗ Network error — cannot reach the remote repository.` /
  `✗ Authentication failed — check your git credentials or SSH key.`
  (also: `✗ GitHub is rate limiting requests or having an outage (HTTP 429)`
  and `✗ GitHub appears to be having an outage — try again in a few minutes`).
  Fetch manually — the fetch is the real check:

  ```
  git -C ~/.hermes/hermes-agent fetch origin main
  ```

  If that succeeds, SSH is fine. Only if you use an ssh-agent should
  `ssh-add -l` list the deploy key; with no agent running (this host's normal
  state), skip the agent check.

- **`hermes update` auto-stashes local changes**: it does **not** error on
  uncommitted changes. It auto-stashes them before pulling
  (`git stash push --include-untracked -m "hermes-update-autostash-<UTC timestamp>"`),
  preceded by the printed line
  `→ Local changes detected — stashing before update...`, then re-applies the
  stash after the update by default. With `--keep-stash` it leaves the stash
  parked and prints
  `ℹ️  Local changes were stashed before updating and were NOT re-applied (--keep-stash).`
  plus `Restore manually with: git stash apply <ref>`.
- Real hazard: an update killed mid-run can leave a parked
  `hermes-update-autostash-*` entry. Procedure: check
  `git -C ~/.hermes/hermes-agent stash list`, inspect
  `git -C ~/.hermes/hermes-agent stash show -p stash@{0}`, then re-apply with
  `git -C ~/.hermes/hermes-agent stash apply stash@{0}` (or `stash pop` once the
  apply is confirmed clean). Do not run another update while an autostash entry
  sits unexamined.

- **Gateway does not start after update**: read the service log first:

  ```
  journalctl --user -u hermes-gateway -n 50
  ```

  Then follow the Rollback path.

- **`Update available: N commits behind` never goes away**: expected if updates
  are deferred on a rolling setup. It is informational, not an error — update
  when you want the changes, not because the line is printed.
