# Archify prototype — merge + MOA gate mechanics (2026-09-30)

**Date:** 2026-09-30 · **Type:** run finish · **Issue:** #26 · **PR:** #27

## Outcome

PR #27 merged via `gh pr merge --squash --delete-branch` → main `f1f21b8`
(17 files, 16,544 insertions, 1 deletion). Branch `feat/26-archify-validate`
deleted. Issue #26 closed (all acceptance criteria met).

Second MOA gate verdict: **APPROVE** — no blockers, no warnings; PII-clean,
evidence-backed, honest. NITs from the gate were applied as a follow-up doc
commit `fdc08bb` before merge (version wording, receipt-sourced metrics label,
squash-history caveat), then merged.

## Gate launch lessons (2026-09-30) — apply to every future gate

- Background gate launches block-buffer stdout: the out file can sit at 0 bytes
  while the gate is healthy and mid-run. Liveness check = `/proc/<pid>` or
  `process(action='wait', session_id=...)`, NOT the output file size. The
  previous window's "died silently with 0 bytes" was a false alarm on this run.
- Launch with `terminal(command="hermes chat -Q --query-file <prompt> -m moa:default > <out> 2>&1", background=true, notify_on_complete=true)`.
  No `nohup`/`disown`/`setsid` (lifecycle guard blocks them) and no `rm` in
  the same command (dangerous-command filter blocks "delete in root path");
  the shell `>` redirect truncates the out file by itself.
- `hermes chat --query-file <path>` avoids `-q "$(cat …)"` shell interpretation.
- process_manage poll/wait requires `session_id`, not `process_id`.
- Gate takes ~5–6 min when the prompt is tight (summarized diff, not inlined);
  poll with `process(action='wait', session_id=..., timeout=180)` repeatedly.
- The final aggregator verdict line is the only thing that counts; the 2
  "[NIT]" fixes suggested were applied because workflow says address all
  findings — both were text-only doc changes (no re-gate needed; the tree moved
  closer to the gate's stated ideal).
- Squash-merge makes the pre-fix intermediate history (absolute paths in
  8bb49a3) harmless on main — never `--no-ff`/rebase such a PR; note now says so.