# ARCHITECTURE — Local Agent Setup (as of 2026-08-11)

> Written as the first committed artifact: *understand before changing* (Mission §1).
> Status: post-performance-cleanup (docker/containerd/tor/ollama/litellm removed), post-reboot (kernel 7.1.8, nvidia-open 610.57 loaded).

## 1. Host

- **OS:** Arch Linux (rolling), kernel 7.1.8-arch, systemd, KDE Plasma (kwin_wayland)
- **User:** local user (uid 1000) · **Hostname:** generic Arch host
- **GPU:** GTX 1650 (laptop) — nvidia-open 610.57, `NVreg_DynamicPowerManagement=0x02` (dGPU sleeps at idle, 3.8W)
- **Disk:** 59G used / ~387G free after cleanup (was 98G used)
- **Privilege path:** `pkexec` (sudo requires password; `sudo -n` fails)

## 2. Hermes Agent

- **Gateway:** runs as systemd **user service** (`hermes-gateway.service`) with linger enabled — survives logout, restarts via `hermes gateway restart` (outside shell only; the agent's own lifecycle guard blocks restart-pattern commands from within)
- **Config home:** `~/.hermes/` (config.yaml, .env, state.db, kanban.db, sessions/, memories/, skills/, scripts/, cron/)
- **Platforms:** Telegram DM (primary)

## 3. Model routing (all cloud LLM APIs — Mission §7)

| Alias | Model | Provider | Notes |
|---|---|---|---|
| default | deepseek-v4-flash | opencode-go (`https://opencode.ai/zen/go/v1`, key `OPENCODE_GO_API_KEY`) | subscription, zero cost; primary |
| pro | deepseek-v4-pro | opencode-go | /model alias |
| code | kimi-k2.7-code | opencode-go | /model alias |
| glm | glm-5.2 | opencode-go | /model alias |
| max | qwen3.8-max | opencode-go | /model alias |
| (aux) | glm-5 | auto-routed | compression/titles; `smart_model_routing` config key is **vestigial** (no logic) |

- Local inference endpoints (ollama :11434, litellm :4000) were **removed** in the 2026-08-11 cleanup — any config references to them are dead and should be purged (see backlog).
- LiteLLM parked at :4000 — **removed**, do not resurrect.

## 4. Cron jobs

| Job | Schedule | Type | Notes |
|---|---|---|---|
| Morning Brief | 07:00 daily | agent + script `morning_context.py` | ~/.hermes/scripts/ |
| Token Usage Report | 07:30 daily | no_agent script `token_usage_report.py` | stdout delivered verbatim |
| post-reboot-verify | one-shot 2026-08-11 | agent | **completed & removed** (verification ran live) |
| used-tiny-price-pull | completed | one-shot | Lenovo ThinkCentre Tiny used-price snapshot |

Scripts live in `~/.hermes/scripts/`: `morning_context.py`, `token_usage_report.py`, `validate-config.sh`, `gateway_restart.sh`, `llm-watchdog.sh` (inventory verified 2026-08-11).

## 5. Skills & memory

- Skills: `~/.hermes/skills/` + bundled categories (github, mlops, productivity, software-development, autonomous-ai-agents…)
- Memory: `memories/` — injected every turn; user profile + personal notes (compact, high-signal)
- **Reusable procedures belong in skills, not memory** (memory = preferences & environment facts)

## 6. Security posture

- Secrets: `~/.hermes/.env` only; `redact_secrets` on; tirith config present; secret-bearing files deleted unread when encountered
- GitHub: `gh` CLI 2.97, token in **system keyring** (outside LLM context), scopes `repo, read:org, gist`
- Never print/commit keys; `pkexec` over sudo-password-in-chat; pkill with exact-name matching only (`-x`, never `-f` — self-SIGTERM footgun)

## 7. Known tech debt (→ backlog)

1. Dead provider references: config may still list ollama/litellm endpoints (removed) — purge & verify config with `validate-config.sh`
2. No automated backup of `~/.hermes` (state.db, kanban.db) — crash = data loss
3. `smart_model_routing` key is vestigial — remove or implement
4. No update policy for Hermes itself (rolling Arch; hermes-agent source checkout at `~/.hermes/hermes-agent`)
5. Overnight power management not yet automated (rtcwake available; firmware wake-from-S5 untested)
6. Deals-monitor design approved but not built (r/bapcsalescanada RSS, craigslist jsonsearch, canadacomputers verified sources)
