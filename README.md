# agent-lab

Autonomous AI engineering workspace. Primary project: **continuously improving the local agent setup** (`~/.hermes` on an Arch/KDE host). Also home to experiments, benchmarks, and ops documentation.

## Visual overview

![Architecture overview](assets/architecture.png)

*Auto-rendered from live state (cron jobs + local repos) by `scripts/render_architecture.py`; refreshed daily and committed only when it actually changes. PII redacted.*

## Layout

```
docs/ARCHITECTURE.md          # the current setup, mapped (understand before changing)
docs/MISSION.md               # the operating charter (verbatim)
docs/DAILY_LOOP.md            # the daily Research → Issue → Implement → Test → Commit → Push loop
docs/AI_ENGINEERING_TRENDS.md # 2025-2026 agentic AI trends reference (sources verified 2026-09-01)
scripts/                      # cron/ops scripts (source of truth; deployed to ~/.hermes/scripts/; check-ops-drift.sh verifies sync)
SECURITY.md                   # secrets policy
```

## Operating principles

- **GitHub is the source of truth.** Work is driven from the issue backlog.
- **Meaningful progress > activity.** One real commit per active day beats a streak.
- **Cheapest reliable model wins.** Cloud LLMs for reasoning/coding; keep provider-independent.
- **Secrets never enter the repo.** See `SECURITY.md`.

## Current status

- Daily loop active (Mon–Fri 09:00 via Hermes cron): inspect → research → one task → implement+test → PR → MOA review gate → merge → issue close → notes.
- 2026-09-07: ops-script drift reconciled (issue #22) — 14 deployed cron/ops scripts imported and templated, `check-ops-drift.sh` added.
- See `docs/ARCHITECTURE.md` for the live picture.
