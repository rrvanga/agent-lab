# AI Engineering Trends 2025–2026

> Reference document · researched & verified 2026-09-01 · sources listed at the end.
> All self-reported adoption figures are attributed to their publisher. Items not personally re-verified are marked `[unverified]`.

## Executive Summary

Agentic AI crossed the line from prototype pattern to production discipline between late 2024 and 2026. Four structural shifts define the period:

1. **A canonical taxonomy replaced folklore.** Anthropic's "workflows vs. agents" split — workflows orchestrate LLM/tool calls through *predefined code paths*, agents let an LLM *dynamically direct* its own process and tool use — became the field's shared vocabulary, along with five named production workflow patterns and the agent-loop patterns (ReAct, Reflection/Reflexion) that preceded them.
2. **The backend standardized.** Two open standards now anchor the stack: **Model Context Protocol (MCP)** for tool integration — donated to the Linux Foundation's new **Agentic AI Foundation** in Dec 2025, with 247 member organizations by Aug 2026 — and **OpenTelemetry** as the tracing substrate (its GenAI semantic conventions still *Development*-status as of 2026-09-01). Orchestration is coalescing around graph runtimes (LangGraph) and framework-agnostic managed platforms (LangSmith Deployment, AWS AgentCore, Gemini Enterprise Agent Platform).
3. **Cost and evaluation became engineering controls.** FinOps Foundation reports 98% of organizations now manage AI spend (up from 31% two years prior). "Tokens meter AI like kWh meter electricity," and a token quota is simultaneously a financial control and an engineering control. Evaluation shifted from grading the model to **testing the system, not the model** — trace/path assertions over outcome-only scoring.
4. **The discipline became teachable (the people layer).** By Sept 2026 the canonical patterns above had been commoditized into installable skills and cohort courses — flagship **Matt Pocock's AI Hero** (creator of Total TypeScript turned full-time AI-engineering educator; self-reported 113,800+ learners, 8,500+ cohort-trained, 25 free installable skills). When a discipline condenses into teachable artifacts it has crossed the adoption chasm — and "web developer → AI engineer" became the era's retraining wave.

The practical through-line across all four research areas: **start simple, verify at every step, and only add agentic complexity where it demonstrably improves outcomes.** Multi-agent systems consume ~15× the tokens of plain chat (agents ~4×); the complexity must earn its keep.

## Implementation Patterns

### The taxonomy that stuck

- **Workflows** — LLMs and tools orchestrated through predefined, deterministic code paths. Predictable, debuggable, cheaper. (Anthropic, Dec 2024)
- **Agents** — LLMs that dynamically direct their own process and tool usage based on environmental feedback in a loop. Flexible, but they trade latency and cost for performance, with compounding errors and divergent trajectories that are hard to control and evaluate.

Anthropic's guidance is consistent and worth quoting as policy: find the simplest solution first — *"may mean not building agentic systems at all,"* since a single optimized LLM call with retrieval and in-context examples often suffices — and add complexity only when it demonstrably improves outcomes.

### Agent-loop patterns

- **ReAct** (arXiv:2210.03629): interleaves reasoning traces with task-specific actions — reasoning induces, tracks, and repairs action plans; actions gather external information. Beats chain-of-thought on HotpotQA/FEVER (less hallucination and error propagation) and imitation/RL baselines by +34% (ALFWorld) and +10% (WebShop).
- **Reflexion** (arXiv:2303.11366): "verbal reinforcement" — the agent reflects on failure signals and stores reflective text in an episodic memory buffer instead of updating weights. 91% pass@1 on HumanEval vs. GPT-4's 80%.
- **Production loop discipline** (Claude Code practice): close the verification loop with runnable checks (tests/build/screenshots); use a separate evaluator; a deterministic `Stop` hook as a gate; a fresh-context subagent as adversarial reviewer so *the agent doing the work isn't grading it*; split explore → plan → implement because performance degrades as context fills.
- **Stopping conditions remain mandatory** — every loop iteration costs tokens; unbounded loops are an expensive failure mode.

### Multi-agent architecture

- Anthropic's Research system is orchestrator-worker at scale: a lead agent plans and spawns 3–5 parallel subagents with separate context windows (compression + separation of concerns); subagents call 3+ tools in parallel — cutting research time up to 90%.
- **Token economics are the binding constraint**: agents use ~4×, multi-agent ~15× the tokens of chat; token usage alone explained ~80% of BrowseComp variance in Anthropic's analysis. Multi-agent only pays off for high-value, heavily parallel work; coding tasks with tight inter-agent dependencies are a poor fit today.
- **Coordination is the hard part**: early versions spawned 50 agents for simple queries — prompts must encode delegation rules and effort scaling (1 agent / 3–10 calls for fact-finding vs. 10+ subagents for complex research).
- **Eval breaks down**: different valid paths mean step-by-step eval is invalid — use end-state evaluation and small early samples.
- The 2026 direction (Anthropic Managed Agents): virtualize agents into three stable interfaces — **session** (append-only event log), **harness** (the loop), **sandbox** (execution) — decoupling "brain from hands"; harness assumptions go stale as models improve.

### Decision matrix

| Pattern | Core Problem | Trade-off | Best Use Case |
|---|---|---|---|
| **Prompt chaining** | Fixed multi-step task that decomposes sequentially | Latency per hop; errors chain downstream | Cleanly separable pipeline with programmatic gates on intermediates |
| **Routing** | Inputs vary in difficulty or type | Extra classification call; misroutes misclassify | Easy → cheap model (Haiku class), hard → capable model (Sonnet class) |
| **Parallelization** | Independent subtasks, or confidence needed | Duplicated cost (N× calls) | Sectioning independent work; multi-run voting |
| **Orchestrator-workers** | Unpredictable runtime decomposition | Coordination overhead; ~15× token burn; eval complexity | Multi-agent research, open-ended exploration |
| **Evaluator-optimizer** | Iterative quality, clear evaluation criteria | Generator + critic doubles cost; needs objective metric | Code with tests, writing with rubrics |
| **ReAct loop** | Interleaved reasoning + action on live feedback | Loop cost; error compounding; stopping conditions required | Interactive tool-using tasks; open-ended problem solving |
| **Reflection / Reflexion** | Learning from failed attempts without weight updates | Episodic-memory overhead | Self-correcting code/answers (HumanEval 91% pass@1) |
| **Graph orchestration (LangGraph)** | Long-running stateful flows: branching, cycles, HITL | Low-level; deterministic/idempotent state discipline; complexity budget | Durable workflows needing resume-after-failure, approvals, fan-out |
| **SDK loop (OpenAI Agents SDK, ADK)** | Standard agent runtime without graph ceremony | Abstraction obscures prompts/responses | Runtime-owned turns, guardrails, handoffs; linear flows |
| **Managed platform (LangSmith Deployment, AgentCore, Agent Platform)** | Skip infra ops; compliance, scale | Vendor coupling; metered pricing [unverified]; region lock-in | Cloud-committed orgs; framework-agnostic runtime needs |

## Infrastructure (The MCP Era)

### Tool standardization: Model Context Protocol

- **Origin**: Anthropic open-sourced MCP on Nov 25, 2024 as "a new standard for connecting AI assistants to the systems where data lives" (spec + SDKs, Claude Desktop support, reference servers; early adopters Block and Apollo). It is a JSON-RPC 2.0 protocol between Host/Client/Server, inspired by the Language Server Protocol; servers expose Resources, Prompts, and Tools.
- **Versioning model**: revisions are `YYYY-MM-DD` strings, bumped *only on backwards-incompatible changes*. Published: `2024-11-05` (initial, HTTP+SSE transport) → `2025-03-26` → `2025-06-18` → `2025-11-25` (anniversary: async operations, statelessness, server identity, official extensions) → **`2026-07-28` (current)**. Clients negotiate via `io.modelcontextprotocol/protocolVersion` in `_meta` or the `MCP-Protocol-Version` header; a new mandatory `server/discover` RPC returns supported versions and capabilities up front.
- **Transports**: `stdio` (client launches server as subprocess; newline-delimited JSON-RPC; env-credential auth) and Streamable HTTP (single MCP endpoint, optional SSE, resumable streams; replaced the 2024 HTTP+SSE transport). Streamable HTTP servers **MUST validate the `Origin` header** (403 on invalid — DNS-rebinding defense), SHOULD bind localhost when local, and SHOULD implement auth.
- **Auth**: OAuth 2.1 (draft-ietf-oauth-v2-1-13) + RFC 8414 / 7591 / 9728 / 8707 resource indicators; OIDC Discovery 1.0 added in 2025-11-25. Authorization is **optional**; servers MUST validate the token audience and MUST NOT pass client tokens upstream (confused-deputy prevention).
- **Adoption** *(Anthropic/LF self-reported)*: by Dec 2025 — 10,000+ active public servers, 97M+ monthly SDK downloads (Python + TypeScript); adopted by Claude, ChatGPT, Cursor, Gemini, Microsoft Copilot, VS Code; infrastructure support from AWS, Cloudflare, Google Cloud, Microsoft Azure; official community MCP Registry launched.

### Governance: the donation that changed the landscape

- **Dec 9, 2025** — Linux Foundation formed the **Agentic AI Foundation (AAIF)** with founding project contributions: Anthropic donated **MCP**, Block contributed **goose**, OpenAI contributed **AGENTS.md**. Platinum members: AWS, Anthropic, Block, Bloomberg, Cloudflare, Google, Microsoft, OpenAI; Gold includes Salesforce, SAP, Snowflake, Datadog, IBM, Oracle, Cisco.
- **Aug 13, 2026** — AAIF grew to **247 member organizations** (+57: 3 Gold, 33 Silver, 21 Associate), with Alibaba, Visa, and Wells Fargo joining as Gold — financial-services and APAC momentum. The **Agentic AI Momentum Report** tracks 116 open-source projects across five layers of the agentic AI stack. MCP Dev Summit Seoul; AGNTCon + MCPCon Japan/China.
- MCP governance was formalized in the 2025-11-25 revision (SEP-932 structure, SEP-1302 working groups) and is unchanged by the donation.

### Security posture — the honest picture

- The spec is **guidance, not enforcement**: consent, data privacy, and tool-safety rules "cannot be enforced at the protocol level." Tool descriptions/annotations "should be considered untrusted, unless obtained from a trusted server" (tool-poisoning mitigation).
- The Security Best Practices doc formally catalogs the **confused-deputy** attack on proxy/gateway servers (client-to-third-party-API bridges) and OAuth authorization-URL validation; SEP-986 adds tool-name guidance.
- **Hard trade-offs**: `stdio` is local-only with env-credential auth (smaller surface); Streamable HTTP enables remote, centrally governed gateway/proxy deployments but widens the surface (DNS rebinding, confused deputy, token passthrough). LF neutrality answers vendor lock-in, but every MCP server remains an attack surface — a neutral home does not solve server supply-chain risk. Rapid version cadence creates churn: version strings and the negotiation header matter.

### Graph orchestration: standardizing the control plane

- **LangGraph** (OSS, MIT): the low-level orchestration runtime for long-running stateful agents — mixes deterministic hand-coded steps with LLM-driven steps in one graph. Differentiators: **durable execution** (checkpointer persists full state after every step keyed by `thread_id`; runs resume exactly where they left off, even a week later — in exchange for strict discipline: deterministic, idempotent, JSON-serializable state with side effects wrapped in tasks), **human-in-the-loop** (`interrupt()` + `Command(resume=...)`), streaming, persistence/memory. Version 1.2.11 (2026-09-01); users include Klarna, Uber, J.P. Morgan, Replit, Elastic.
- **OpenAI Agents SDK** (OSS; Swarm successor): three primitives — agents, **handoffs**, **guardrails** (parallel validation, fail-fast) — plus Sessions (persistent memory), tracing, HITL. Python-first; use the raw Responses API when you want to own the loop yourself.
- **Temporal**: general-purpose durable execution — workflows "resume automatically after a crash, a network timeout, or a multi-day wait for a human." Framework-agnostic *substrate* that wraps agent frameworks (published integrations: LangGraph, OpenAI Agents SDK, ADK, Vercel AI SDK, Pydantic AI, Mastra); patterns: Approval (HITL via Signals), Saga, Long-Running Activity, Entity Workflow.
- **Google ADK 2.0**: graph workflows "to weave deterministic code with adaptive AI reasoning"; managed context; Python/TS/Go/Java/Kotlin; one-command deploys to Cloud Run/GKE or managed Agent Runtime.
- **Managed platforms went framework-agnostic**: LangSmith Deployment (renamed from LangGraph Platform, Oct 2025 — HITL/background-task/multi-agent APIs, versioning/rollbacks, A2A/MCP/Agent Protocol), Gemini Enterprise Agent Platform (runs LangGraph, LangChain, ADK, LlamaIndex, AG2, A2A agents; VPC-SC, CMEK, HIPAA), AWS Bedrock AgentCore ("any framework, any model"; auth/access control for MCP servers, tracing, evals). Also: Semantic Kernel (Microsoft, lightweight, multi-language) and Vellum (low-code, versioned).

### Orchestration decision guidance

- **Linear / short-lived flows**: OpenAI Agents SDK (or the plain Responses API) — *not* a graph framework.
- **Long-running, cyclic, HITL-heavy, full control**: LangGraph self-hosted + LangSmith for observability/evals; LangSmith Deployment when you don't want the infra ops.
- **Durability independent of agent stack**: Temporal, wrapping whatever framework you choose.
- **Cloud-committed, framework-agnostic, compliance-heavy**: AWS AgentCore / Gemini Enterprise Agent Platform / LangSmith Deployment; Vellum if low-code matters.
- **Enterprise Microsoft / multi-language teams**: Semantic Kernel.
- **Rule of thumb**: adopt graph/durable execution only if you need resume-after-failure, rollback, branching, or human approval — otherwise the SDK's loop is the simpler correct answer. Graphs overcomplicate single-turn chat, simple RAG, and linear pipelines.

## The Path to Production

### Observability & tracing

- **OpenTelemetry GenAI semantic conventions** are **Status: Development — not stable** as of 2026-09-01. They define events, exceptions, metrics, **model spans** and dedicated **agent spans**, provider conventions (Anthropic, Azure AI Inference, AWS Bedrock, OpenAI) and MCP conventions. The work moved to the standalone `open-telemetry/semantic-conventions-genai` repo; attribute churn is real (PR #363, 2026-09-01, deprecated per-message `finish_reason` in favor of response-level). **Pin versions.**
- Platforms now standardize on OpenTelemetry-based trace capture (LLM calls, tool calls, sessions, agent graphs): **Langfuse** ("based on OpenTelemetry to increase compatibility and reduce vendor lock-in"; trace → monitor → datasets → experiment → evaluate loop; LLM-as-judge evals on production traces), **Arize Phoenix** (OpenInference/OTLP; auto-instrumentation; `px setup` traces Claude Code/Codex/Cursor/OpenCode), **OpenLIT** (OTel-native; telemetry auto-redacted before leaving the stack; GPU+cost dashboards), **LangSmith** ("traces are the record of what your agents did in production"; online evals, automation rules), **Braintrust** (active observability — surfaces critical patterns from traces).
- **Trade-off**: full per-tool-call traces are raw material for both debugging and FinOps attribution — but they cost; client-side redaction (OpenLIT) and self-hosting (Phoenix, Langfuse, OpenLIT) are the standard mitigations.

### Cost controls (FinOps for AI)

- **Framing** (FinOps Foundation, 2026-08): FinOps and "Tokenomics" are complementary projections of one discipline — FinOps owns budget, allocation, ownership, cadence; Tokenomics owns model/efficiency design and cost-per-outcome viability. "Tokens meter AI like kWh meter electricity" — explicitly *not* token counting. FinOps-only → spending freeze; Tokenomics-only → unfunded efficiency program.
- **Who sets the budget** (2026-08): cost-to-serve is driven by **operational behavior and engineering decisions, not model price**. Leakage layers: model mismatch, idle/dark usage, prompt bloat (input:output ratio), poor cache hit rate, retry waste, verbosity, unnecessary tool calls. **Division of labor**: finance sets the envelope, engineering enforces quotas/tiered triggers *where spend happens*, FinOps supplies evidence. **"A token quota is simultaneously a financial control and an engineering control, and it only works if both sides set it together."** One-year contracts; ~12-month forecast horizon. **"A discount on the wrong model is not a saving"** — audit auto/smart routing (real incident: "automatic mode" quietly ran a frontier model for `git checkout`).
- **State of FinOps 2026**: **98% of respondents manage AI spend, up from 31% two years prior**; practitioners with executive engagement report 2–4× more influence.
- **Agentic FinOps** (2026-08): adoption is gated by delegated authority and org context, not capability. **Bounded autonomy** is the only documented path: narrow decision spaces, limits expressed in policy (not prompts), evidence before action, human-gated execution. **"Add a spending cap and a step limit… an agent that loops without end is not just slow, it is expensive."**

### Real-time agent evaluation

- **Test the system, not the model.** Agent non-determinism compounds across every tool call; identical final outputs can hide 3 vs. 30 file reads with wildly different cost/latency/failure modes; capability is gated by architecture. Plain-LLM baselines expose capability gaps; assert the path when the path matters (**trace assertions**), add cost assertions (`type: cost, threshold: 0.50`), make responses machine-checkable (`output_schema`). (promptfoo)
- **Trajectory vs. outcome**: Anthropic's philosophy is outcome-first (SWE-bench Verified, test-verifiable output); promptfoo/DeepEval grade tool-by-tool (span/trace assertions). **2025/26 practice combines both** — end-state evaluation for multi-agent runs, trace-graded steps for single agents.
- **Guardrails**: routing easy queries to smaller cost-efficient models (parallel screening model beats same-call guardrails); sandboxed testing; careful ACI/tool design (absolute filepaths alone fixed SWE-bench errors).
- **Tooling**: DeepEval — pytest-native evals for CI/CD, 50+ research-backed metrics, span-level scoring (TaskCompleteness), synthetic goldens, and its OTel instrumentation collects *metric names only* (never prompts/outputs). promptfoo — retries HTTP 429/502/503/504/524 with exponential backoff (respecting `retry-after`; overridable to fail-fast), AIMD adaptive concurrency (halve on rate-limit hit, +1 on success, pre-decrease under 10% quota), per-provider/key isolation, on-disk response caching (14-day TTL) as a cost control.
- **Evals-as-cost-control**: "where output quality holds as token consumption falls" is an evaluation question before a cost question — the same tooling serves both.

### Recommended actions for this repo's stack

- Adopt OTel-based tracing for the agent pipeline (Langfuse or Phoenix self-hosted fit a homelab posture); pin GenAI semconv versions — they are pre-stable.
- Enforce the FinOps discipline already in place here: spending caps + step limits on agent loops and cron-driven agents; audit the model-routing layer periodically (a discount on the wrong model is not a saving).
- Treat the existing MOA review gate as the repo's system-level eval; add trace assertions for the cheap, high-signal agent paths (tool calls, step counts, cost per run) before adding more agentic complexity.

## The Skills Landscape (the people layer)

- **The retail signal.** By 2026-09-01 the discipline documented above crossed the adoption chasm in the education market: enterprise patterns are being commoditized into *installable skills* — one-command setup, AGENTS.md-driven, structurally identical to this repo's SKILL.md model — and cohort courses for working developers. When a discipline condenses into teachable artifacts, it has stabilized.
- **Flagship: Matt Pocock's AI Hero** *(verified 2026-09-01 from totaltypescript.com / mattpocock.com / aihero.dev — publisher figures)*: the creator of **Total TypeScript** (industry-standard TS course), ex-XState core team and Vercel developer advocate, now an AI-engineering educator full-time. AI Hero = "the engineering process for working with coding agents, from an idea to shipped, reviewed code" — the same idea→ship spine this repo's own workflow uses.
- **Self-reported scale**: 113,800+ developers learning, 8,500+ trained in cohorts, 25 free skills — all marked `[unverified]` per this document's convention (publisher figures).
- **The curriculum mirrors this doc's findings**: `/to-spec → /to-tickets → /implement → /code-review` (prompt chaining + evaluator-optimizer as a named main flow); `/grill-with-docs`, `/research`, `/wayfinder` (routing/parallelization/orchestrator-workers); a complete **AGENTS.md guide**, plan-mode intro, "never run `/init`" (context discipline — cf. the Claude Code best-practices loop notes above); **TDD as a first-class skill** (cf. runnable checks in the loop discipline); **AFK agents** ("Ralph") = bounded autonomy, the only documented path in the Agentic FinOps section above.
- **The cohort course "AI Coding for Real Engineers"** *(waitlist, 2026-09-01)*: two weeks covering context gathering, planning, steering, feedback loops, AFK agents, and **human-in-the-loop review** — the orchestration section's HITL pattern, as a course outline. "Trained in cohorts: 8,500+" — the retraining wave is measurable.
- **What it signals for this repo**: (1) the SKILL.md/AGENTS.md pattern is industry-validated — skills are the emerging distribution format for agent-workflow knowledge; (2) the bottleneck has moved from *knowing the tools* to *engineering with agents* — which is exactly what the emergent courses teach; (3) creators are a legitimate trend-signal source — the education layer reports where the field's trajectory is *adopted*, not just where vendors push it.

## Sources

Patterns & agents:
- https://www.anthropic.com/engineering/building-effective-agents · https://www.anthropic.com/engineering/built-multi-agent-research-system · https://www.anthropic.com/engineering/claude-code-best-practices · https://www.anthropic.com/engineering/managed-agents · https://arxiv.org/abs/2210.03629 · https://arxiv.org/abs/2303.11366 · https://openai.github.io/openai-agents-python/

MCP & governance:
- https://www.anthropic.com/news/model-context-protocol · https://www.anthropic.com/news/donating-the-model-context-protocol-and-establishing-of-the-agentic-ai-foundation · https://modelcontextprotocol.io/ · https://modelcontextprotocol.io/llms.txt · https://modelcontextprotocol.io/docs/2026-07-28/learn/versioning.md · https://modelcontextprotocol.io/specification/2025-11-25 · https://modelcontextprotocol.io/specification/2025-11-25/basic/transports · https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization · https://modelcontextprotocol.io/specification/2025-11-25/changelog.md · https://modelcontextprotocol.io/docs/2025-11-25/tutorials/security/security_best_practices.md · https://www.linuxfoundation.org/press/linux-foundation-announces-the-formation-of-the-agentic-ai-foundation · https://www.linuxfoundation.org/press/agentic-ai-foundation-welcomes-57-new-members-gaining-major-financial-services-players-and-apac-leaders

Orchestration:
- https://langchain-ai.github.io/langgraph/concepts/ · https://langchain-ai.github.io/langgraph/concepts/durable_execution · https://langchain-ai.github.io/langgraph/concepts/human_in_the_loop · https://pypi.org/project/langgraph/ · https://www.langchain.com/langsmith/deployment · https://docs.temporal.io/ · https://docs.temporal.io/ai.md · https://adk.dev/ · https://cloud.google.com/vertex-ai/generative-ai/docs/agent-engine/overview · https://aws.amazon.com/bedrock/agentcore/ · https://learn.microsoft.com/en-us/semantic-kernel/overview/ · https://docs.vellum.ai/home/getting-started/overview

Production (observability / FinOps / evals):
- https://raw.githubusercontent.com/open-telemetry/semantic-conventions-genai/main/docs/gen-ai/README.md · https://github.com/open-telemetry/semantic-conventions-genai · https://langfuse.com/docs · https://docs.arize.com/phoenix/ · https://docs.openlit.io/ · https://docs.smith.langchain.com/ · https://www.braintrust.dev/docs · https://www.finops.org/insights/finops-tokenomics-fit-together/ · https://www.finops.org/insights/setting-ai-budget/ · https://www.finops.org/insights/agentic-finops-adoption/ · https://www.promptfoo.dev/docs/guides/evaluate-coding-agents/ · https://www.promptfoo.dev/docs/configuration/rate-limits/ · https://www.promptfoo.dev/docs/configuration/caching/ · https://deepeval.com/

Skills & learning landscape:
- https://www.totaltypescript.com/ · https://mattpocock.com/ · https://www.aihero.dev/