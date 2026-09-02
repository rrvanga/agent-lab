# Learning notes — 2026-09-02

## PR #16 merged: guarded rtcwake nightly shutdown + wake (issue #5)

- MOA gate ran in background on the final diff (`b119ab1`) — **VERDICT: APPROVE** (merge-ready).
- One optional P2 nit flagged: missing trailing newlines on five files (cosmetic, explicitly optional and harmless by reviewer's own wording). Merged `b119ab1` as-reviewed via squash (`f112582`) per the "no filler commits" rule — a cosmetic newline churn + full re-gate was not worth a second review cycle. Verdict captured to file for the record before merging.
- Merge: `gh pr merge 16 --squash --delete-branch` → `f112582` on main. Issue #5 auto-closed by the squash commit message ("issue #5").

## Issue #17 fixed: "unknown toolset 'a2a'" warning on every chat run

- **Root cause:** `~/.hermes/config.yaml` declared the `a2a` toolset in three places
  (`platform_toolsets.cli` L245, `known_plugin_toolsets.cli` L281, `platforms.a2a.enabled: true` L321)
  but the `a2a-platform` plugin is bundled-not-enabled and `~/.hermes/plugins/` is empty → warning at `hermes_cli/cli.py:5308` on every startup.
- **Decision: REMOVE (not enable).** Evidence: no A2A env vars, no docs refs, no gateway/cron/kanban/journal usage; refs present even in the earliest known-good backup (long-standing, but never wired). No intent signal → removing stale refs is strictly cheaper and zero-risk vs. exposing a new localhost network surface.
- **Fix applied (not by direct YAML edit — the update policy + config CLI):**
  - `hermes config set platform_toolsets.cli '["browser", ...]'` (full list minus `a2a`)
  - `hermes config set known_plugin_toolsets.cli '["spotify"]'`
  - `hermes config set platforms.a2a.enabled 'false'`
  - Pre-change backup: `/tmp/config.yaml.bak-issue17`; known-good backup auto-refreshes via llm-watchdog (5m timer) per update policy.
- **Accepted:** `hermes chat -Q -q` runs clean (no Unknown-toolsets warning, PONG returned) and `hermes tools list` still enables `terminal` + all intended toolsets. Issue #17 closed.

## Lessons for the loop

1. **Config changes to Hermes must go through `hermes config set`** — direct edits to `~/.hermes/config.yaml` via the patch tool are blocked (lifecycle guard), and the CLI is the sanctioned path anyway. The "not recognized config key" notice from `hermes config set` for `platform_toolsets.cli` is a schema-warning only; source reads these keys via `config.get(...)`, so the set is effective.
2. **Review-gate P2 nits:** an explicitly-optional P2 with a "merge-ready" verdict is mergeable as-is; don't churn the reviewed SHA for cosmetics.
3. **`.review/` scratch stays local** — research/learning notes are tracked under `docs/notes/`, but review probe scripts/verdicts have never been committed; keep it that way (README-level cleanliness).