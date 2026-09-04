# Research notes — 2026-09-04

## Run outcome

- **Task selected:** close issue #19 — `nightly-shutdown.sh` daytime poweroff for early-start midnight-spanning windows (round-3 P1) + missing time-format guard on `NIGHT_START`/`NIGHT_END`.
- **Implementation:** `fix/nightly-window-start-guard` → `000c379` (commit) → PR #20 (3 files, +110/-5: `valid_hhmm()` format guard + `start >= 20:00` floor + tests T10–T13 + POWER_MANAGEMENT.md).
- **Verification:** 13/13 harness tests pass; sabotage check (bound removed in /tmp copy) → T10 FAILS (test bites); probe matrix green (12:00..00:00 @13:00 → exit 2, no poweroff; 19:59 refused; 20:00 boundary allowed; malformed 24:00/25:00 refused).
- **Review gate:** MOA verdict **APPROVED** — "No [P1] findings. No path admits a daytime poweroff; the P1 issue is closed. Safe to merge." Three non-blocking [P2]s: shared-helper refactor opportunity (valid_hhmm vs validate_wake_time), non-normalized "03:7" tolerated (harmless in context), 2000-int comment suggestion.
- **Merged:** PR #20 → squash commit `49d754c` on main; branch deleted; issue #19 closed.

## Backlog status

- Zero open issues, zero open PRs after merge. Backlog drained. 09-03 research note committed retroactively (was left untracked by the previous run).

## Trends (GitHub trending daily, 2026-09-04)

- Skills wave continues: `mattpocock/skills` (247.5k★, +1.6k/day), `anthropics/skills` (173.7k★), `addyosmani/agent-skills` (92k★) still at the top; `NousResearch/hermes-agent` (240.9k★, +774). Convention convergence on SKILL.md frontmatter persists — our `ai-skill-security-auditing` remains relevant for provenance.
- `magnitudedev/magnitude` (1.97k★, +161/day): continues steady growth as an inference server for agent tools; kept as an eval-day candidate, not a blind install.
- Google's `timesfm` (30.7k★, +1.6k) — time-series, out of scope.
- Noise/novelty: `DietrichGebert/ponytail` (+2.1k), `affaan-m/ECC`, `JuliusBrussee/caveman`, `blader/humanizer` (+1.2k), `averygan/reclip`, `bannedbook/fanqiang` — not relevant to the lab.
- `Imbad0202/academic-research-skills` (46k★, +496) — academic-skills-adjacent; possible reference for future research-synthesis work, not adopted.
- `Gitlawb/openclaude` (32.4k★) — open-source agent CLI; noted, we already standardize on opencode.

## HF trending (agent search, by likes)

- `yuxinlu1/gemma-4-12B-agentic-fable5-composer2.5-v2-3.5x-tau2-GGUF` — 1,521 likes, **601k downloads** (top downloads by far); agentic Gemma-4-12B fine-tune. A 12B-class agentic model that could plausibly run on the local box — benchmark candidate vs the llama-server fleet (needs VRAM check: ~8-9GB at Q4).
- `Qwen/Qwen-AgentWorld-35B-A3B` (710 likes, 57k downloads; qwen3_5_moe, arxiv:2606.24597) + `unsloth/Qwen-AgentWorld-35B-A3B-GGUF` (235 likes, 444k GGUF downloads) — same candidate as yesterday; local box can't host 35B-A3B comfortably.
- `agentica-org/DeepCoder-14B-Preview` (683 likes; MIT, DeepSeek-R1-distill base), `InternScience/Agents-A1` (637 likes; qwen3_5_moe VLM), `agentica-org/DeepScaleR-1.5B-Preview` (584; MIT) — eval candidates only.
- `openbmb/AgentCPM-Explore` (418; Qwen3-4B base), `openbmb/AgentCPM-Report` (305), `fishaudio/fish-agent-v0.1-3b` (275; cc-by-nc-sa-4.0) — noted, no action.

## Decision

- One task this run: close issue #19 (P1). Done — merged `49d754c`, issue closed.
- No new project selected; backlog drained. Carry-forward candidates for future runs: magnitude eval day; 12B agentic GGUF benchmark (gemma-4-12B-agentic — fits-local-class); skills-wave provenance auditing on any adopted third-party skills.

## Learnings

- MOA gate backgrounding: the terminal wrapper reported the background `hermes chat` as "exited" at ~11–37s with 0 bytes, **but the orphaned child kept running and wrote the full verdict to the output file**. Rule: never kill/relaunch on the wrapper's early "exited" — check `pgrep -af 'hermes chat'` and read the FULL output file; snapshot the verdict file as soon as it appears. First attempt (`-q "$(cat ...)"` inline) actually completed fine; the reported failure was a wrapper artifact, not a real abort.
- The complete verdict (aggregator line + `session_id`) only appears at the very end of the file — verify a trailing `session_id:` line before trusting it.