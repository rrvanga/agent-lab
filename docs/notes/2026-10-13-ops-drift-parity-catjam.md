# Ops-drift parity: a concurrent cron job can rewrite the deployed scripts mid-run (issue #36)

**Date:** 2026-10-13
**Scope:** `scripts/check-ops-drift.sh`, `scripts/morning_context.py`, `scripts/token_usage_report.py`

## What happened

Issue #36 asked for one additive row (`step-5-preview-free`) in the two `GO_RATES` tables so
that `check-ops-drift.sh` (repo `scripts/` vs deployed `~/.hermes/scripts/`, compared with
`cmp -s`) stops WARNing. Commit `f892f66` did exactly that and drift checked clean mid-run.

Later in the same run, drift was **dirty again**: both deployed files had been rewritten at
`2026-10-13T20:45:06` with a new `cat-jam-free` row and a comment re-align of `ox-alpha-free`.
The writer was identified as a **concurrent Hermes cron job** (Go adaptive monitor,
schedule `0 8-22/2 * * *`, `last_run` finished `2026-10-13T20:46:12` status `ok`) — i.e. the
same automation family that produced `step-5-preview-free` produced this row too.

`cat-jam-free` was independently verified as real and live on 2026-10-13 (unauthenticated,
HTTP 200):

- `https://opencode.ai/zen/v1/models` — 86 ids, `cat-jam-free` at index 3
- `https://opencode.ai/zen/go/v1/models` — 39 ids, `cat-jam-free` at index 34
- `step-5-preview-free` present in both

## Resolution

Commit `e06cbf4` reconciled the repo to the deployed bytes (add `cat-jam-free`, re-align the
`ox-alpha-free` comment), then verified `py_compile`, `cmp` parity on both files, and
`check-ops-drift.sh` rc=0. PR #37 carries both commits.

## Lessons

1. **Drift cleanliness is a moving target.** A green `check-ops-drift.sh` mid-run is not a
   result — re-run it immediately before merging and before closing the issue. Concurrent cron
   jobs *do* write into `~/.hermes/scripts/`, and they can fire between the check and the merge.
2. **Identify the writer before deciding the direction of reconciliation.** Match the deployed
   file mtime against `~/.hermes/cron/jobs.json` `last_run`/`status` to name the job. Here the
   deployed copy was the newer, verified-correct state, so the repo was reconciled *toward* the
   deployed copy (the reverse of the usual repo→deploy direction). Direction must follow
   verified truth, not habit.
3. **Look up every model id in the diff against the live catalogs.** Neither the deployed files
   nor the repo are authoritative for pricing ids; `curl` the two `/v1/models` endpoints and
   confirm the id exists before propagating it.
4. **`opencode run -f <file> "<message>"` swallows the message.** With the `-f` array flag the
   CLI consumed the positional message as a second file path and failed with
   `Error: File not found: <message text>`, making no edit. Inline the spec in the message
   (`opencode run --dir <repo> "$(cat spec.md)"`) or put the message first.
5. **Carried-forward numbers are not automatically true.** The reconciled comment says
   `paid39/zen85`; the paid count (39) matches the live fetch, the zen count measured 86 (the
   list likely grew between 20:45 and 20:53). Carried verbatim to preserve byte-parity, and
   disclosed as an ambiguity rather than silently "fixed" — fixing it would require re-writing
   the live ops scripts and re-verifying them.
6. **Stop superseded gates.** A MOA gate started on a diff that a later commit supersedes
   should be killed, not awaited — it loops in context compaction and burns budget on a
   revision that will never be merged.
