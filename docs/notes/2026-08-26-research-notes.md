# Research notes — 2026-08-26 (daily loop, research phase)

Context: day's ONE task = PR #14 rework (docs accuracy). Research gathered candidate
ideas for the NEXT issue, not implemented here.

## Candidate 1 — Apache Maka (Incubating): local-first agent workspace
- https://github.com/apache/maka — "local-first AI agent workspace. Model messages,
  tool calls, tool results, permission decisions, and termination events are
  recorded as an append-only log."
- Directly relevant to this mission's theme (autonomous agents + recoverable work):
  append-only execution logs make agent runs auditable and resumable. Hermes
  sessions already persist conversation history; a comparable discipline could
  apply to agent-lab's own run artifacts (currently: docs/notes + issue threads).
- Possible next task: assess Maka's log/permission model, extract 2-3 practices
  agent-lab could adopt (e.g. permission-decision logging, durable task progress).
- Requires: repo read + gap analysis against agent-lab's current loop. Low risk,
  no live-system changes.

## Candidate 2 — AI agent memory benchmarks: LoCoMo / LongMemEval / BEAM
- mem0 "State of AI Agent Memory 2026" (mem0.ai/blog/state-of-ai-agent-memory-2026):
  benchmark results + 21 framework integrations; LoCoMo, LongMemEval, BEAM are the
  three benchmarks used today.
- Relevance: this Hermes profile's MEMORY.md is at 99% capacity (2,193/2,200 chars)
  and USER.md at 98% — memory hygiene is a live operational concern.
- Possible next task: evaluate the three benchmarks' criteria against Hermes memory
  behavior (MEMORY.md/USER.md compaction, skill curation), then tune retention
  rules (what to promote/evict) using benchmark-informed heuristics.
- Requires: read mem0 blog + benchmark papers; config/behavior audit; no code risk.

## Not selected this run
- Deals-monitor removal (filed as issue #15; code lives in a reversible stash:
  `git stash list` in agent-lab, message "wip: deals-monitor removal").
- Price-checker / web-data scraping: memory says price checkers were dropped;
  only resurrect if the user asks.

## Recommended pick for next run
Candidate 1 (Maka assessment) — self-contained, mission-aligned, low risk.