#!/usr/bin/env bash
# Local LLM backup watchdog for Hermes.
# Start-on-demand backup: when the cloud LLM (opencode-go) is unreachable /
# throttling, bring the local Gemma llama-server ONLINE so Hermes still has a
# thinking brain. When the cloud recovers, tear the local server down to
# reclaim the 4GB GPU + ~12GB RAM (only if idle).
#
# Emits stdout ONLY on a state transition -> the no_agent cron delivers the
# message to Telegram; on a no-change tick it stays silent (watchdog pattern).
#
# NOTE (llm-watchdog.sh does the DISASTER path: restore known-good config);
# this one does the RESILIENCE path: local compute as a live fallback.
set -u
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="${ENV_FILE:-$HERMES_HOME/.env}"
CACHE_DIR="$HOME/.hermes/.cache"
mkdir -p "$CACHE_DIR"

SERVER="$HOME/.local/llama-b10488/llama-server"
MODEL="$HOME/models/gemma-4-12b-it-Q4_K_M.gguf"
PORT=8081
BASE="http://127.0.0.1:$PORT"
LOG="$HOME/models/server_backup.log"
HEALTH_URL="$BASE/health"
STATE_FILE="$CACHE_DIR/local_backup_state"   # "up" | "down"
LOCK="$CACHE_DIR/local_backup.lock"
BOOT_TIMEOUT=120   # seconds to wait for health after launching

cloud_healthy() {
  local BASE_URL API_KEY code
  BASE_URL=$(grep -E '^OPENCODE_GO_BASE_URL=' "$ENV_FILE" | head -1 | sed -e 's/^[^=]*=//' -e 's/^"//' -e 's/"$//' -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  API_KEY=$(grep -E '^OPENCODE_GO_API_KEY=' "$ENV_FILE" | head -1 | sed -e 's/^[^=]*=//' -e 's/^"//' -e 's/"$//' -e 's/\r$//' -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then
    return 2
  fi
  code=$(curl -s -o /dev/null -m 20 -w '%{http_code}' \
      -X POST "$BASE_URL/chat/completions" \
      -H "Authorization: Bearer $API_KEY" \
      -H "Content-Type: application/json" \
      -H "x-opencode-session: sess-local-backup-watchdog" \
      -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"ping"}],"max_tokens":1}')
  [ "$code" = "200" ]
}

local_up()      { [ "$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$HEALTH_URL" 2>/dev/null)" = "200" ]; }
local_idle()    {  # true if server up and no slot is mid-generation
  if ! local_up; then return 1; fi
  # 200 + "state":"idle" ; busy -> state busy, or the health returns 503 while generating
  local body
  body=$(curl -s -m 3 "$HEALTH_URL" 2>/dev/null)
  case "$body" in
    *'"state":"idle"'*) return 0 ;;
    *'"status":"ok"'*) return 0 ;;   # older health responses
    *) return 1 ;;
  esac
}

start_local() {
  if local_up; then return 0; fi
  # only one boot at a time: atomic lock so concurrent runs never both spawn
  if ! mkdir "$LOCK" 2>/dev/null; then
    # another boot already in progress / lock held -> stay silent, server presumably coming up
    return 3
  fi
  local SERVER_PID
  # daemonize: cron runs this standalone, so setsid is the correct primitive here
  setsid nohup "$SERVER" -m "$MODEL" --device Vulkan1 -ngl 22 -sm none -c 2048 \
    -b 2048 -ub 512 -t 12 -tb 12 -ctk q8_0 -ctv q8_0 \
    --port "$PORT" --host 127.0.0.1 > "$LOG" 2>&1 < /dev/null 9>&- &
  SERVER_PID=$!
  # wait for health
  local waited=0
  while [ "$waited" -lt "$BOOT_TIMEOUT" ]; do
    if local_up; then rmdir "$LOCK" 2>/dev/null; return 0; fi
    # early bail if the server dies on boot
    if ! kill -0 "$SERVER_PID" 2>/dev/null; then
      rmdir "$LOCK" 2>/dev/null
      return 1
    fi
    sleep 5; waited=$((waited + 5))
  done
  rmdir "$LOCK" 2>/dev/null
  return 1
}

stop_local() {
  if ! local_up; then return 0; fi
  # only stop when idle — never kill a server mid-request
  if ! local_idle; then echo "local-backup: cloud recovered but local server is BUSY — leaving it up."; return 1; fi
  pkill -f "^$SERVER" 2>/dev/null
  local waited=0
  while local_up && [ "$waited" -lt 30 ]; do sleep 2; waited=$((waited + 2)); done
  if ! local_up; then echo "local-backup: cloud is back; local server stopped (GPU/RAM reclaimed)."; return 0; fi
  echo "local-backup: cloud recovered; tried to stop local server but it is still responding — verify manually."
  return 1
}

LOCK_FILE="$CACHE_DIR/local_backup_watchdog.lock"
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  exit 0
fi

UP=$(local_up && echo up || echo down)
STATE_WAS=$(cat "$STATE_FILE" 2>/dev/null || echo down)
STATE_NOW="$STATE_WAS"

cloud_healthy; CLOUD_RC=$?
if [ "$CLOUD_RC" -eq 0 ]; then
  # cloud fine -> server should be down (start-on-demand)
  if [ "$UP" = "up" ]; then
    stop_local
    [ $? -eq 0 ] && STATE_NOW="down"
  else
    # server already down (died/stopped outside watchdog) -> reconcile state
    STATE_NOW="down"
  fi
else
  if [ "$CLOUD_RC" -eq 2 ]; then
    # credentials missing -> unknown/abort: leave server as-is, no transition message
    echo "$STATE_NOW" > "$STATE_FILE"
    exit 0
  fi
  # cloud failing -> server should be up
  if [ "$UP" = "down" ]; then
    start_local; START_RC=$?
    if [ "$START_RC" -eq 0 ]; then
      echo "☁️→🖥️  Cloud LLM is failing/unreachable — local Gemma backup is now ONLINE at :$PORT (start-on-demand). Continuing so you still have a thinking brain."
      STATE_NOW="up"
    elif [ "$START_RC" -ne 3 ]; then
      # only emit FAILED when start_local actually tried to boot and failed
      echo "❌ Cloud LLM failing AND local backup FAILED to start (see $LOG). Manual intervention may be needed."
      STATE_NOW="down"
    fi
    # rc==3 -> another boot in progress; stay silent, server presumably coming up
  fi
  # server already up on a failing cloud -> nothing new to report
fi

echo "$STATE_NOW" > "$STATE_FILE"
exit 0
