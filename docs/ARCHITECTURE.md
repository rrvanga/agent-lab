# ARCHITECTURE — Local Agent Setup (as of 2026-09-07)

> Written as the first committed artifact: *understand before changing* (Mission §1).
> Status: post-performance-cleanup (docker/containerd/tor/ollama/litellm removed 2026-08-11), ops-script drift reconciled (2026-09-07, issue #22).

## 1. Host

- **OS:** Arch Linux (rolling), kernel 7.1.8-arch, systemd, KDE Plasma (kwin_wayland)
- **User:** local user (uid 1000) · **Hostname:** generic Arch host
- **GPU:** GTX 1650 Max-Q 4 GB (laptop) — nvidia-open 610.57.04, `NVreg_DynamicPowerManagement=0x02` (dGPU sleeps at idle)
- **RAM:** 23 GiB · **Disk:** 88G used / 357G free (20%)
- **Privilege path:** `pkexec` (sudo requires password; `sudo -n` fails)

## 2. Hermes Agent

- **Gateway:** runs as systemd **user service** (`hermes-gateway.service`) with linger enabled — survives logout, restarts via `hermes gateway restart` (outside shell only; the agent's own lifecycle guard blocks restart-pattern commands from within)
- **Config home:** `~/.hermes/` (config.yaml, .env, state.db, kanban.db, sessions/, memories/, skills/, scripts/, cron/, profiles/)
- **Platforms:** Telegram DM (primary); peers via bot-bridge (git-queue message pump, `~/.hermes/bridge-repo`)
- **Kanban:** `~/.hermes/kanban.db` — durable work queue, gateway spawns workers

## 3. Model routing (cloud-first; local fallback on demand)

| Alias | Model | Provider | Notes |
|---|---|---|---|
| default | deepseek-v4-flash | opencode-go (`https://opencode.ai/zen/go/v1`, key `OPENCODE_GO_API_KEY`) | subscription, zero cost; primary |
| pro | deepseek-v4-pro | opencode-go | /model alias |
| code | kimi-k2.7-code | opencode-go | /model alias |
| glm | glm-5.2 | opencode-go | /model alias |
| max | qwen3.8-max | opencode-go | /model alias |
| (aux) | glm-5 | auto-routed | compression/titles |

- **Local backup:** llama.cpp Vulkan build at `~/.local/llama-b10488/llama-server`, gemma-4-12b-it Q4_K_M at `~/models/`, health at `http://127.0.0.1:8081/health`. Cloud-first policy: the local server starts on demand only — the cron watchdog was **disabled 2026-09-08**, replaced by the in-process on-demand fallback (`try_activate_fallback` boot hook); no automatic startup otherwise. GTX 1650 4 GB is too small for the 12B carry-forward benchmark candidate.
- Ollama/litellm endpoints were **removed** in the 2026-08-11 cleanup — dead references purged; do not resurrect.

## 4. Cron jobs (roster snapshot; jobs.json is the source of truth)

| Job | Schedule | Type | Script / notes |
|---|---|---|---|
| Morning Brief | 07:00 daily | agent | `morning_context.py` feeds context |
| Token Usage Report | 07:30 daily | no_agent | `token_usage_report.py` — Go-dollar tracking |
| daily-hermes-backup | 06:30 daily | no_agent | `hermes-backup-quick.sh` |
| llmcost daily update | 09:30 daily | no_agent | `llmcost_update.sh` |
| skills vault sync | 09:45 daily | no_agent | `skills_vault_sync.sh` |
| awesome-local-ai drip | 10:00 daily | no_agent | `awesome_drip.sh` |
| architecture diagram refresh | 11:00 daily | no_agent | `architecture_diagram.sh` |
| cron-sentinel | 08:00 daily | no_agent | `cron_sentinel.py` — dormant-job alarm |
| Go bucket watchdog | 08:00–22:00 every 2h | no_agent | `go_bucket_watchdog.py` — spend limits |
| Go adaptive monitor | 08:00–22:00 every 2h | agent | model-routing decisions |
| thermal-watch | every 5m | no_agent | `thermal_watch.py` — CPU 92/95°C sustained |
| bot-bridge-watch | every 2m | agent | peer-bot message pump (git queue) |
| local-llm-backup-watchdog | every 5m | no_agent | `local_backup_watchdog.sh` — **disabled 2026-09-08** (see §3, in-process fallback) |
| battery-band-monitor | every 360m | agent | completed — superseded by root `battery-band-watchdog.timer` |
| sleuth-judge-sweep | every 360m | agent | sleuth review layer |
| daily-engineering-loop | Mon–Fri 09:00 | agent | this mission (agent-lab) |
| til daily entry | Mon–Fri 10:30 | agent | public TIL note |
| skillspector weekly delta watch | Mon 09:00 | no_agent | `skillspector_watch.sh` |
| autonomy-window | 14:30 daily | agent | autonomous work block |

**Scripts are versioned in this repo (`scripts/`) and deployed to `~/.hermes/scripts/`** (cron accepts bare filenames only, resolved inside that dir). `scripts/check-ops-drift.sh` verifies every cron-referenced script exists in both places and flags content drift — run it after any live script edit.

## 5. Skills & memory

- Skills: `~/.hermes/skills/` + bundled categories (github, mlops, productivity, software-development, autonomous-ai-agents…) — **reusable procedures belong in skills, not memory**
- Memory: `memories/` — injected every turn; user profile + personal notes (compact, high-signal: preferences & environment facts)
- Knowledge base: Obsidian vault (`~/obsidian-vault`) via AppImage; TIL notes separate/public

## 6. Security posture

- Secrets: `~/.hermes/.env` only; `redact_secrets` on; secret-bearing files deleted unread when encountered
- GitHub: `gh` CLI, token in **system keyring** (outside LLM context), scopes `repo, read:org, gist`
- **This repo is PUBLIC** — PII bar is absolute: no usernames, home paths, emails, keys, or internal hostnames. Deployed scripts are templated (`$HOME`/`expanduser`) before import.
- Never print/commit keys; `pkexec` over sudo-password-in-chat; pkill with exact-name matching only (`-x`, never `-f`)

## 7. Backlog / known tech debt

Resolved (2026-08-11…09-07): dead provider refs purged; `~/.hermes` backup automated (`hermes-backup-quick.sh` daily + gpg snapshot archives); Hermes update policy documented (hermes-agent skill, source checkout); overnight power management automated (`nightly-shutdown.sh` + rtcwake + root battery-band watchdog).

Open:
1. Ops-script drift — reconciled 2026-09-07 (issue #22): 14 deployed cron/ops scripts imported and templated, drift checker added. Next live-script edit should be made in the repo, then re-deployed.
2. Deployed scripts still outside the repo (not cron-referenced): `adaptive_monitor.py`, `battery-band-monitor.sh`, `bridge_poll.sh`, `dgpu-runtime-pm*.sh`, `go-ping.sh`, `kanban-check.sh`, `skills_vault_scrub.py`, `sleuth_pending.sh` — document or import in a future pass.
3. Local inference manual-only (paused 2026-09-05) — resume policy TBD; GTX 1650 4 GB can't run the 12B carry-forward benchmark candidate.
