# Research notes — 2026-08-31 (daily loop, research phase)

Context: day's ONE task = advance issue #5 (overnight power management:
rtcwake shutdown + scheduled wake) with the safe prep work. Research below
feeds NEXT-task selection.

## Environment signal: RTC wake plumbing (issue #5 groundwork)
- RTC is rtc_cmos (ACPI PNP0B00): `/sys/class/rtc/rtc0/wakealarm` exists and
  is readable (0644, root-write), `/proc/driver/rtc` healthy, battery OK.
- Hardware accepts wake-alarm through the standard sysfs contract; the open
  question is firmware wake-from-S5, which is exactly the empirical 5-min
  test issue #5 prescribes. That live test needs an authorized window (root,
  machine goes offline briefly) — cannot run inside the cron loop.
- Morning Brief cron confirmed at 07:00 (`hermes cron list`), Token Usage
  Report at 07:30 → wake target 06:45 local.

## Candidate 1 — multi-provider gateway with routing (new, worth watching)
- https://github.com/hkqr/my-free-code (537★, created <5d ago): open-source
  multi-provider AI gateway for coding agents; model routing + streaming.
  Directly relevant to agent-lab's model-routing work (fallback chains,
  adaptive-monitor). Not building on it now — the gateway/monitor stack is
  healthy — but a routing-pattern comparison would be a good future issue.

## Candidate 2 — agent memory (Datalog)
- https://github.com/JordyZomer/lemmalog (229★): stratified rules,
  provenance-tracked facts, incremental derivation for LLM agent memory.
  Interesting contrast to mem0-style vector memory; keep on the watch list —
  mem0 retention tuning (08-28 note) remains the nearer-term memory task.

## Candidate 3 — execution-recovery controller
- https://github.com/usedotai/dot-reflex (80★): agent execution-recovery
  controller for coding/tool-using agents. Relevant to reliability/monitoring
  (agent-lab's llm-watchdog, kanban worker retries). Young project; observe.

## Still pending from 08-28
- Apache Maka incubation (run-artifact conventions: append-only event log,
  permission-decision logging) — pattern assessment candidate, not yet an
  issue.

## Recommended pick for next run
Either (a) run the issue #5 live S5 test (needs user/authorized window —
see docs/POWER_MANAGEMENT.md stage 2), then decide shut-down vs suspend path;
or (b) if #5 is closed by then, the Maka run-artifact-conventions issue.