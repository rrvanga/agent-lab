# Research notes — 2026-09-03

## Backlog status

- Zero open issues at start (all 9 closed); no open PRs. Backlog drained after PR #16/#18 merges.
- Standing research found a real gap instead: the round-3 review verdict's P1 ("daytime poweroff for early-start midnight-spanning windows") is **still on `main`** — empirically reproduced (`12:00..00:00` + `WAKE_TIME=13:30` @13:00 → `systemctl poweroff`, rc=0). The 09-02 learning note claims MOA APPROVE on `b119ab1`, but on-disk `.review/round3-verdict.md` (same SHA) says CHANGES REQUIRED; either way, `main` is exploitable. → Issue #19 opened, fix in progress (`fix/nightly-window-start-guard`).

## Agent/tooling trends (2026-09-03)

- Huge "skills wave": `mattpocock/skills`, `anthropics/skills`, `addyosmani/agent-skills`, `obra/superpowers` all trending on GitHub daily. Agent skill libraries are converging on the same file convention we already use (SKILL.md frontmatter). We already audit skills for security (`ai-skill-security-auditing`) — this wave increases the importance of provenance checks before adopting third-party skills.
- `magnitudedev/magnitude` (1.9k★, +130/day): open-source inference server pluggable into Hermes/OpenCode/Claude Code etc. Local-model inference; adjacent to our `local-llm-fallback` + llama-server setup. Candidate for an eval day, not a blind install.
- `google-research/timesfm` (time-series foundation model) — out of scope for now.
- HF trending (agent search): `Qwen/Qwen-AgentWorld-35B-A3B` (71k likes; 35B-A3B MoE, agent-tuned; GGUF available) — worth benchmarking against the local-llm fallback fleet when budget allows (fits the 35B-A3B profile discussed in the desktop-shopping research; local box can't host it — RAM/VRAM bound).
- `agentica-org/DeepCoder-14B-Preview` (code-gen), `SWE-bench/SWE-agent-LM-32B`, `InternScience/Agents-A1` — noted as eval candidates only.

## Decision

- Selected ONE task: close issue #19 (daytime-poweroff validation hole + format guards in `nightly-shutdown.sh`). It is the highest-value reliability item found in research, empirically verified, with a clear review-mandated fix.