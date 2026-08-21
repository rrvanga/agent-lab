# 2026-08-21 — Issue #3 closed: vestigial smart_model_routing key stripped (docs + live config)

## What & why
Issue #3 tracked the `smart_model_routing` config key: `docs/ARCHITECTURE.md` noted it as
"vestigial (no logic)" in the model-routing table and carried it as tech-debt item 3, while the
live `~/.hermes/config.yaml` still had a `smart_model_routing: {enabled: false}` block. Investigation
confirmed the key is write-only in hermes-agent source (setup wizard `setup.py` writes `enabled: False`,
config whitelist `config.py` admits it, blank-slate test asserts the default) — **no logic anywhere
reads it**. Dead config implying a nonexistent feature → remove or implement; chose remove.

## What changed
- **Repo (PR #13, branch `feat/remove-smart-model-routing`):**
  - `docs/ARCHITECTURE.md`: dropped the "vestigial" clause from the (aux) glm-5 model-routing row;
    removed backlog item 3 and renumbered 4-6 → 3-5. 1 file, +4/-5.
- **Live:** `hermes config unset smart_model_routing` (2026-08-21 ~09:03; pre-unset backup
  `~/.hermes/config.yaml.bak-smr-20260821-090301`). `hermes config check` clean after removal.

## Acceptance gates (all green)
- Repo-wide grep: zero `smart_model_routing` occurrences in tracked files (docs + assets).
- Live config: key absent; `hermes config check` exit 0 (no errors).
- MOA review gate: **VERDICT: APPROVE** — no required fixes. Reviewer independently verified
  zero stale refs, clean backlog renumbering, and confirmed "vestigial" is the precise word
  (write-only key). One optional nit (PR body live-config box) resolved by ticking it after the
  unset landed — the reviewer's live check then confirmed the key was already gone.

## PR
https://github.com/rrvanga/agent-lab/pull/13 — MERGED 2026-08-21 (squash, `--delete-branch`), main SHA `bff26d8`.
Issue #3 auto-closed via squash message `Closes #3`.

## Learnings
- **Verify both halves of "dead config" chores:** docs references AND the live config key can
  linger independently. The repo-side fix (docs-only PR) was drafted first; the live-key removal
  was the second half and this run completed it — issue body should track both explicitly.
- **`patch` tool refuses edits under `~/.hermes/` (config guard) — use `hermes config unset <key>`
  instead.** Direct file patching of live Hermes config is blocked by design; the CLI is the
  sanctioned path (backup first: `cp config.yaml config.yaml.bak-<ts>`).
- **Write-only config keys are "vestigial" by definition:** a key can be whitelisted in
  `config.py`, written by setup, and asserted in tests while still being dead weight — check for
  *readers*, not just existence, before labeling anything functional.
- **MOA gate on a tiny docs PR is still worth the full ceremony:** the reviewer independently
  verified the live config state (found the key gone right after the unset) and cross-checked
  renumbering for dangling refs — caught nothing, but the verification is cheap insurance.
- **Backlog renumbering:** `deals-monitor.md`/`deals_monitor.py` reference "issue #6" — that's the
  *GitHub* issue number, not a backlog-list position; renumbering the list does not touch it.

## Refs
- commits: `502e39c` (docs change, PR #13) → merged as `bff26d8` (main)
- Issue #3 auto-closed by squash message.