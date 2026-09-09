#!/usr/bin/env bash
# LLM connectivity watchdog for Hermes. Runs WITHOUT an LLM (no_agent cron),
# so it survives exactly the failure mode of the 2026-08-11 incident (broken
# model connection -> agent cannot think -> cannot fix itself).
#
# Probe the endpoint every tick. Healthy  -> silent (watchdog pattern).
# After MAX_FAILS consecutive failures -> snapshot current state, restore the
# last known-good .env + config.yaml, restart the gateway, and report.
set -u
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="$HERMES_HOME/.env"
CONFIG_FILE="$HERMES_HOME/config.yaml"
BACKUP_DIR="$HERMES_HOME/backups/known-good"
BROKEN_DIR="$HERMES_HOME/backups/broken_state"
STATE_FILE="$HERMES_HOME/.cache/llm_watchdog_fails"
MAX_FAILS=3

BASE_URL=$(grep -E '^OPENCODE_GO_BASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d ' ')
API_KEY=$(grep -E '^OPENCODE_GO_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d ' ')
if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then
  echo "LLM watchdog: OPENCODE_GO_BASE_URL / OPENCODE_GO_API_KEY missing from $ENV_FILE — manual fix required."
  exit 1
fi

HTTP_CODE=$(curl -s -o /dev/null -m 20 -w '%{http_code}' \
  -X POST "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -H "x-opencode-session: sess-llm-watchdog" \
    -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"ping"}],"max_tokens":1}')

if [ "$HTTP_CODE" = "200" ]; then
  rm -f "$STATE_FILE"
  exit 0   # healthy — silent
fi

FAILS=0
[ -f "$STATE_FILE" ] && FAILS=$(cat "$STATE_FILE" 2>/dev/null || echo 0)
FAILS=$((FAILS + 1))
mkdir -p "$(dirname "$STATE_FILE")"
echo "$FAILS" > "$STATE_FILE"

if [ "$FAILS" -lt "$MAX_FAILS" ]; then
  echo "⚠️ LLM watchdog: endpoint returned HTTP $HTTP_CODE (failure $FAILS/$MAX_FAILS). If this persists I will restore the known-good config automatically."
  exit 0
fi

echo "⚠️ LLM watchdog: $MAX_FAILS consecutive failures (HTTP $HTTP_CODE). Restoring known-good config and restarting gateway…"
STAMP=$(date +%Y%m%d_%H%M%S)
mkdir -p "$BACKUP_DIR" "$BROKEN_DIR"
[ -f "$ENV_FILE" ] && cp "$ENV_FILE" "$BROKEN_DIR/.env.$STAMP"
[ -f "$CONFIG_FILE" ] && cp "$CONFIG_FILE" "$BROKEN_DIR/config.yaml.$STAMP"

RESTORED=""
if [ -f "$BACKUP_DIR/.env" ]; then
  cp "$BACKUP_DIR/.env" "$ENV_FILE" && RESTORED=".env"
fi
if [ -f "$BACKUP_DIR/config.yaml" ]; then
  cp "$BACKUP_DIR/config.yaml" "$CONFIG_FILE" && RESTORED="$RESTORED config.yaml"
fi
rm -f "$STATE_FILE"

if [ -n "$RESTORED" ]; then
  systemctl --user restart hermes-gateway 2>&1
  echo "🛠️  Restored: $RESTORED (broken state snapshotted to $BROKEN_DIR/). Gateway restarted. If this looks wrong, tell the user — the snapshot has the exact pre-restore state."
else
  echo "❌ No known-good backup at $BACKUP_DIR — manual intervention needed. Rescue path: opencode CLI has its own config/credentials and can edit $HERMES_HOME regardless of Hermes' model state."
fi
