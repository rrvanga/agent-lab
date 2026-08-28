# Research notes — 2026-08-28 (daily loop, research phase)

Context: day's ONE task = finish PR #14 (Hermes update-policy runbook, docs/UPDATE.md)
to the satisfaction of the 2026-08-24 MOA gate, then merge + close issue #4. Research
gathered below feeds NEXT-task selection, not this run's implementation.

## Candidate 1 (re-confirmed) — Apache Maka: momentum, not just a repo
- Status check on the 08-26 pick: https://github.com/apache/maka is now INCUBATING
  at the ASF (created 2026-05-27, 3,954 commits, Apache-2.0). It was the #1
  trending repo this week (+1,978 stars/wk, 3,785 total) — no longer an obscure
  experiment, plausibly the space to watch.
- Architecture worth studying for agent-lab run-artifact discipline:
  - Append-only Runtime Event Log (model messages, tool calls, tool results,
    permission decisions, termination events) → auditable + resumable runs.
  - SQLite operational state (packages/storage); sessions can branch/retry/regenerate.
  - Sandbox boundary for tools; MCP client (packages/mcp).
  - `maka run --graph` spawns isolated git-worktree operators — parallels
    agent-lab's multi-agent / delegation patterns.
- Concrete candidate task (still low risk, no live-system changes): extract 2-4
  practices agent-lab could adopt today — e.g. permission-decision logging in
  docs/notes, durable task-state checkpoints per run (not just issue threads),
  and a deliberate "run artifact = append-only" convention on shared files.
- Note: no Apache release yet (incubation) — do not build on top of it; use as
  pattern reference only.

## Candidate 2 (unchanged) — memory-benchmark-informed retention tuning
- mem0 "State of AI Agent Memory 2026" (LoCoMo / LongMemEval / BEAM) remains the
  reference for MEMORY.md/USER.md hygiene — still at 99%/98% capacity. Deferred
  again; the compaction reminder keeps it live.

## Environment observation (relevant to update policy)
- hermes-agent upstream moved 121 commits between 08-27 (v0.20.6 update) and today
  (08-28). The "N commits behind" count in the runbook varies run-to-run by
  design; cadence question (time-based vs commit-count-based update trigger) is
  worth a future issue if upstream keeps this pace.

## Recommended pick for next run
Candidate 1 (Maka pattern assessment → agent-lab run-artifact conventions),
narrowed to a deliverables-backed issue with 2-4 concrete adoptions.