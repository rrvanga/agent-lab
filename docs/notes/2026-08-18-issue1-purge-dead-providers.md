# 2026-08-18 — Issue #1 closed: dead local-endpoint provider purge + validator

## What & why
The 2026-08-11 cleanup removed local inference endpoints (ollama :11434, litellm :4000), but two dead keys
(`HERMES_CUSTOM_LOCALHOST_11434_API_KEY`, `HERMES_CUSTOM_LOCALHOST_4000_API_KEY`) lingered in `~/.hermes/.env`.
Issue #1 tracked purging them and making the regression class detectable.

## What changed
- **Live:** both dead keys purged from `~/.hermes/.env` (backup `/tmp/hermes-env-backup-<ts>.env`); no other
  `HERMES_CUSTOM_*` keys remain. `config.yaml` was already clean.
- **Repo (PR #12, branch `feat/purge-dead-providers`):**
  - `scripts/validate-config.sh` (NEW): ported from live (byte-identical baseline) + new **section 4
    dead local-endpoint reference check** (`--check-refs-only` mode) scanning `.env` + `config.yaml` for
    `:11434` / `:4000` refs and the two dead key names.
  - OpenCode review pass (approve-with-fixes, 5 fixes): check 1 now **exits 1** on inline comments
    (previously flagged-but-passed — same bug class the script exists to catch); port regex tightened
    to `[^0-9]:(11434|4000)([^0-9]|$)` (kills `:1143490` / `2026:4000` false positives); inline comments
    stripped before matching; missing-file guard; YAML list-dash cosmetic fix.
  - `docs/ARCHITECTURE.md`: auto-refreshed diagram.
- **Live sync:** reviewed artifact copied to `~/.hermes/scripts/validate-config.sh` (byte-identical verify).

## Acceptance gates (all green)
- `validate-config.sh --check-refs-only`: exit 0 live & in repo. Pre-purge it caught both dead keys (exit 1).
- Full `validate-config.sh`: exit 0 (check 1 OK, endpoint probe HTTP 200, check 4 clean; doctor residuals
  are pre-existing npm vulns + missing optional API keys — unrelated, not chased).
- `bash -n` clean; OpenCode process-compliance pass.
- MOA review gate (2026-08-19): **APPROVE-WITH-FIXES** — no blocking defects; reviewer rebuilt
  section 4 in isolation and ran 9 synthetic cases (dead value+inline-comment, dead key-name,
  config.yaml ref, no-targets, clean, false-positive battery). Logic correct, `set -u` safe,
  no secret exposure, fail-closed exit semantics correct. 3 cosmetic nits logged, all
  non-blocking/not-required: (1) non-refs-only mode prints "clean" on unperformed scan when both
  targets missing — worth revisiting if the check is ever wired into a full-run gate; (2) a .env
  line matching BOTH dead key-name and value regex prints the flag twice; (3) config.yaml KEYWORD
  display label could mangle `:` in quoted YAML — display-only, detection unaffected. None chased
  this run (merge priority; logged as future polish).

## PR
https://github.com/rrvanga/agent-lab/pull/12 — MERGED 2026-08-19T16:05:23Z (squash, `--delete-branch`).

## Learnings
- `opencode run` self-test fixtures hit Hermes' `external_directory` auto-reject when written to /tmp;
  constrain scratch fixtures to the repo (`tests/scratch-tmp/`) and instruct deletion — worked cleanly.
- OpenCode caught a real latent bug in the ported baseline (check 1 flagged inline comments but exited 0):
  porting validated-elsewhere scripts still deserves a fresh review pass, not a blind diff.
- The moa-review gate prompt stays fast when it summarizes the diff; the full diff is appended for reference
  only (141-line prompt incl. diff = ~10 min runtime).
- Gateway reload skipped: `/tmp/gw_reload.sh` absent (07:55 reboot cleared /tmp) — prerequisite not met by design.

## Refs
- commits: `e86cf76` (port baseline), `07e6b4f` (diagram), `ffd8fe5` (OpenCode fixes)
- PR #12 → merged as `main` HEAD: `f3c332f97c44e8969ff2523d8f057d7295030100` (`f3c332f`)
- Issue #1 auto-closed by squash message (`closes #1`). Live script stayed byte-identical to merged artifact.