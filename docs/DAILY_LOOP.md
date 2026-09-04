# DAILY_LOOP.md — Operating Procedure

## The loop (Mission §2)

```
Research → Issue → Implement → Test → Branch+PR → Review → Merge → Update issue → Record learnings
```

## Daily cadence (working days)

1. **Inspect:** `gh issue list` on this repo + `git pull` — pick from backlog
2. **Research:** ~15 min on new AI developments (GitHub trending, Hugging Face, arXiv, engineering blogs) — filter for: AI agents, coding agents, agent memory, evaluation, MCP/tool use, model routing, autonomous SWE, cloud LLM infra
3. **Select ONE task:** meaningful, from backlog; skip if nothing is worthwhile (no filler commits)
4. **Implement + test** on a **feature branch** (never on `main`): `git switch -c feat/<slug>` (small experiments first; keep ≤2 active projects). **All code changes are made via the OpenCode CLI** (`opencode`): hand it detailed requirements (objective, constraints, files involved, acceptance criteria), then review its diff before committing
5. **PR workflow:**
   - Push the branch, open a PR via `gh pr create --fill`
   - **Review gate (MOA):** route the diff through the Mixture-of-Agents preset — `hermes chat -Q -q "<review prompt with diff>" -m moa:default` (fan-out: deepseek-v4-pro + glm-5.2 → qwen3.8-max aggregator). Address findings; iterate until clean
     - The gate takes 10+ min; start it in the background (`> /tmp/moa_review.out 2>&1 &`) and poll the **output file** — the terminal wrapper may report the process as "exited" with 0 bytes within ~10–40s while the orphaned `hermes chat` child is still running. Do NOT relaunch on the wrapper's early "exited" status: verify with `pgrep -af 'hermes chat'` first, snapshot the output file as soon as it holds a trailing `session_id:` line, and treat ONLY that complete verdict as authoritative (a partial file is not a verdict)
   - Merge via `gh pr merge --squash` (or `--delete-branch`); never push straight to `main`
6. **Update the issue** (objective/approach/acceptance criteria); close when done
7. **Record:** notes in `docs/notes/` — what worked, what failed, what was learned

## Quality gates

- No meaningless commits — progress > streak
- Cheapest model that reliably completes the task (Mission §7)
- Issues carry: objective, proposed approach, acceptance criteria
- **Authorization required before:** deleting repos, destroying data, exposing secrets, financial commitments, destructive infra changes (Mission §9)
- Never commit secrets (SECURITY.md)

## Slack windows

- `git pull` at the start of every session; never push on top of unknown remote state
- After a reboot: verify gateway + services before starting the loop
