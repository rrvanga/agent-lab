# 2026-08-24 — PR #14 MOA review gate — VERDICT RECORD

## Final verdict
**CHANGES REQUIRED** — three items to fix before merge. See below.

## Evidence summary
All single-source claims verified live against the system as of 2026-08-24
(version line, unit file, known-good layout, dry-run availability). The 808-behind
count and the session note corroborate each other; git now reports 1 behind for
this very reason. No secrets/PII in the doc. Style matches docs/backup.md.

## Finding 1 — Troubleshooting: invented error string (must fix, line 2 of Troubleshooting)
Doc claims error state `ERROR: update interrupted, working tree dirty`.
Search of the full Hermes checkout (hermes_cli/ and subcommands/) finds
**ZERO** occurrences of `update interrupted` or `working tree dirty` as an
error string. The only place the dirty-tree concept appears is an upstream
runbook comment in main.py:6134. The command `git stash pop` also does not
appear in update_cmd.py's help flow (only `git stash list` and `git stash
drop`). The section must be rewritten to cite the real strings from
update_cmd.py / subcommands/update.py, or clearly marked as hypothetical.

## Finding 2 — Backup example appears fabricated (must fix, Pre-flight step 4)
The doc's example output `hermes-backup-20260824_150000.tar.gz.gpg (63.1 MB,
14 kept)` cannot be reproduced on this system: ~/.hermes-backups contains
**9** archives (last dated 20260816_133014, ~70MB); no 20260824_150000
archive exists; the largest archive is 79,754,634 bytes (~76MB), not 63.1MB;
and a live run prints `... (9 kept)` because RETENTION=14 is only the script
default, not the current count. Any example claiming a specific new file,
size, and count must match what the actual system prints.

## Finding 3 — Dry-run output sequence: conjured arrow line (should fix, Pre-flight step 1)
Source of truth (update_cmd.py:2998-3066): the real output is exactly
`⚕ Update available: N commits behind origin/main.` + `  Run '...' to
install.` — there is NO `→ Fetching from origin...` line preceding it (that
string exists only as a comment inside the fetch helper at update_cmd.py:2998,
not as printed output). The doc's example block shows a `→ Fetching...` line
that is not emitted at that point. Harmless only if dry-run --check actually
prints it; but the code shows it does not reach that branch. Remove the
conjured line or qualify it as commentary.

## Minor / advisory (not blockers)
- SSH troubleshooting: `ssh-add -l` fails here (RC=2, no ssh-agent running;
  systemd ssh-agent.service inactive, gpg-agent-ssh.socket active) and there
  is no ~/.ssh/config Host github.com block — so "must list the hermes deploy
  key" is unverifiable/inaccurate on this box. Suggest generalizing (e.g.
  check your SSH key is known to the agent/service) rather than asserting a
  deploy key.
- `hermes-update` convenience wrapper is not mentioned; fine (not required).
- No secrets/PII in the doc; style consistent with docs/backup.md.

## Refs
- ~/dev/agent-lab/docs/notes/2026-08-24-issue4-hermes-update-policy.md
- Findings verified live 2026-08-24 ~14:30 PDT.