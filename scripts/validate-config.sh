#!/usr/bin/env bash
# Pre-flight / post-edit validation for Hermes .env + config.
# Catches the 2026-08-11 incident class: inline comments in .env values
# silently corrupting URLs (e.g. "KEY=https://x  # comment" -> 404 on every call).
# Run BEFORE and AFTER any model/provider/key change:
#   bash ~/.hermes/scripts/validate-config.sh
set -u
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="$HERMES_HOME/.env"

echo "== 1. .env inline-comment check (the 2026-08-11 bug) =="
BAD=0
while IFS= read -r line; do
  case "$line" in
    ''|\#*) continue ;;   # skip blank lines and full-line comments
  esac
  if printf '%s' "$line" | grep -q '^[A-Za-z_][A-Za-z0-9_]*=.*#'; then
    KEY="${line%%=*}"
    echo "  BAD: $KEY contains an inline '#' — the comment becomes part of the value."
    echo "       Remove it; comments belong on their own line."
    BAD=1
  fi
done < "$ENV_FILE"
[ "$BAD" = "0" ] && echo "  OK: no inline comments."

echo "== 2. LLM endpoint probe (key never printed) =="
BASE_URL=$(grep -E '^OPENCODE_GO_BASE_URL=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d ' ')
API_KEY=$(grep -E '^OPENCODE_GO_API_KEY=' "$ENV_FILE" | head -1 | cut -d= -f2- | tr -d '"' | tr -d ' ')
if [ -z "$BASE_URL" ] || [ -z "$API_KEY" ]; then
  echo "  ERROR: OPENCODE_GO_BASE_URL / OPENCODE_GO_API_KEY not found in $ENV_FILE"
  exit 1
fi
CODE=$(curl -s -o /dev/null -m 20 -w '%{http_code}' \
  -X POST "$BASE_URL/chat/completions" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-flash","messages":[{"role":"user","content":"ping"}],"max_tokens":1}')
echo "  POST $BASE_URL/chat/completions -> HTTP $CODE"
if [ "$CODE" = "200" ]; then
  echo "  OK: endpoint reachable."
else
  echo "  FAIL: endpoint not returning 200. Do NOT apply config changes until this passes."
  exit 1
fi

echo "== 3. hermes doctor =="
hermes doctor 2>&1 | tail -20 || true
