# Research notes — 2026-09-01

## Focus (per MISSION §4): agents, coding agents, memory, evaluation, MCP/tool use, model routing, autonomous SWE, cloud LLM infra

### Hugging Face trending (search=agent)

- `agentionai/Qwen3.8-Flash-Next-ROCmFP4-FAST-imatrix-GGUF` — 177B FP4-quantized Qwen3.8-Flash-Next with ROCm-focused packaging; 11.5k likes. Signals: AMD ROCm inference is a growing quant/packaging target (relevant to our local-LLM initiatives on this box).
- `yuxinlu1/gemma-4-12B-agentic-fable5-composer2.5-v2-3.5x-tau2-GGUF` — 12B agentic-tuned Gemma with a very long name; 557k likes. Datapoint on the agentic fine-tune trend for smaller runnable models.
- `balarajr/triage-hospital-agent` — domain agent example; not directly relevant to our loop.

### GitHub trending (since=daily, language-agnostic sweep)

- `K-Dense-AI/scientific-agent-skills` — 41.2k stars, +1,980 today. Sells "scientific-agent skills" (Claude skills ecosystem) — high-velocity growth suggests the skills-packaging wave (SkillSpector territory, cf. ai-skill-security-auditing) is still expanding. Nothing actionable for the loop, but worth one watch.
- `VoltAgent/awesome-design-md` — 112k★ aggregator list (agentic design). Aggregators keep smashing star counts; not a reason to pivot.
- `affaan-m/ECC` — 245k★; pattern managers (spawn-manage-kill) — similar shape to our own delegated/subagent orchestration. Validates the multi-agent orchestration direction without new action.

### Verdict / selection

No new project warranted — consistent with the ≤2 active projects rule. The local agent project remains the core; the overnight power-management groundwork (issue #5 / PR #16) is the selected task for today. No model-routing or cost signals worth a config change (the Go bucket + adaptive-monitor 2h rewiring already covers provider health).

### Misc observations

- ROCm FP4 quant packaging growing on HF — keep in mind for future local-LLM experiments (VRAM-limited box).
- Skills-packaging trend continues (scientific-agent-skills) — we already operate skills with a security audit posture.