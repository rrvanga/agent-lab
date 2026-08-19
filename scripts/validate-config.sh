#!/usr/bin/env bash
# Pre-flight / post-edit validation for Hermes .env + config.
# Catches the 2026-08-11 incident class: inline comments in .env values
# silently corrupting URLs (e.g. "KEY=https://x  # comment" -> 404 on every call).
# Run BEFORE and AFTER any model/provider/key change:
#   bash ~/.hermes/scripts/validate-config.sh
set -u
HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
ENV_FILE="$HERMES_HOME/.env"

CHECK_REFS_ONLY=0
[ "${1:-}" = "--check-refs-only" ] && CHECK_REFS_ONLY=1

run_dead_refs_check() {
  echo "== 4. Dead local-endpoint reference check =="
  REF_BAD=0
  SCANNED=0
  for FILE in "$ENV_FILE" "$HERMES_HOME/config.yaml"; do
    [ -f "$FILE" ] || continue
    SCANNED=$((SCANNED + 1))
    while IFS= read -r line || [ -n "$line" ]; do
      printf '%s' "$line" | grep -qE '^[[:space:]]*(#.*)?$' && continue
      if [ "$FILE" = "$ENV_FILE" ]; then
        KEY="${line%%=*}"
        case "$KEY" in
          HERMES_CUSTOM_LOCALHOST_11434_API_KEY|HERMES_CUSTOM_LOCALHOST_4000_API_KEY)
            echo "  dead: .env key $KEY"
            REF_BAD=1
            ;;
        esac
        VALUE="${line#*=}"
        VALUE="${VALUE%%#*}"
        if printf '%s' "$VALUE" | grep -qE '(localhost|127\.0\.0\.1):(11434|4000)([^0-9]|$)'; then
          echo "  dead: .env key $KEY"
          REF_BAD=1
        fi
      else
        LINE="${line%%#*}"
        if printf '%s' "$LINE" | grep -qE '(localhost|127\.0\.0\.1):(11434|4000)([^0-9]|$)'; then
          KEYWORD=$(printf '%s' "$LINE" | sed -e 's/^[[:space:]]*//' -e 's/^-*[[:space:]]*//' -e 's/:.*//' -e 's/[[:space:]].*//')
          echo "  dead: config key $KEYWORD"
          REF_BAD=1
        fi
      fi
    done < "$FILE"
  done
  if [ "$SCANNED" = "0" ]; then
    echo "  SKIP: no scan targets found ($ENV_FILE / config.yaml missing)"
    if [ "$CHECK_REFS_ONLY" = "1" ]; then
      exit 1
    fi
  fi
  if [ "$REF_BAD" = "1" ]; then
    echo "fix: remove these dead entries"
    exit 1
  fi
  echo "dead-endpoint check: clean"
}

if [ "$CHECK_REFS_ONLY" = "1" ]; then
  run_dead_refs_check
  exit
fi

echo "== 1. .env inline-comment check (the 2026-08-11 bug) =="
BAD=0
[ -f "$ENV_FILE" ] || { echo "  SKIP: $ENV_FILE not found."; exit 1; }
while IFS= read -r line || [ -n "$line" ]; do
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
if [ "$BAD" = "1" ]; then
  echo "  FIX REQUIRED: resolve the inline comments above, then re-run."
  exit 1
fi
echo "  OK: no inline comments."

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

run_dead_refs_check
