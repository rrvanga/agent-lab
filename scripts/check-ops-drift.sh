#!/usr/bin/env bash
# Ops-script drift checker: reconcile cron-referenced scripts between the repo
# canonical copies (scripts/) and the deployed HERMES scripts dir.
#
# Read-only (no writes) — safe to run at any time. Emits one line per finding:
#   OK:     referenced script present & identical in both places
#   ERROR:  referenced script missing from the repo or HERMES side (exit 1)
#   WARN:   referenced script present but contents differ (no exit-code effect)
#   INFO:   repo-only / local-only files (informational)
# Exit codes: 0 = no ERRORs; 1 = at least one ERROR; 2 = jobs.json unreadable.
# Deps: bash, grep, python3 (json parsing — no jq required).
set -u

REPO_SCRIPTS="${REPO_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
HERMES_SCRIPTS="${HERMES_SCRIPTS_DIR:-$HOME/.hermes/scripts}"
CRON_JOBS="${HERMES_CRON_JOBS:-$HOME/.hermes/cron/jobs.json}"

QUIET=0
for arg in "$@"; do
  [ "$arg" = "--quiet" ] && QUIET=1
done

if [ ! -r "$CRON_JOBS" ]; then
  echo "ERROR: jobs.json not found or unreadable at: $CRON_JOBS" >&2
  exit 2
fi

PY_OUTPUT="$(python3 - "$CRON_JOBS" <<'PYEOF'
import json, os, sys

try:
    with open(sys.argv[1], encoding="utf-8") as fh:
        data = json.load(fh)
except Exception as exc:
    sys.stderr.write(f"ERROR: could not parse jobs.json ({sys.argv[1]}): {exc}\n")
    sys.exit(2)

names = set()

def walk(node):
    if isinstance(node, dict):
        for key, value in node.items():
            if key == "script" and isinstance(value, str):
                names.add(os.path.basename(value))
            else:
                walk(value)
    elif isinstance(node, list):
        for item in node:
            walk(item)

walk(data)
print("\n".join(sorted(names)))
PYEOF
)"
PY_RC=$?

if [ "$PY_RC" -ne 0 ]; then
  exit 2
fi

mapfile -t CRON_SCRIPTS <<< "$PY_OUTPUT"

RC=0
for S in "${CRON_SCRIPTS[@]:-}"; do
  [ -n "$S" ] || continue
  REPO_FILE="$REPO_SCRIPTS/$S"
  HERMES_FILE="$HERMES_SCRIPTS/$S"
  if [ -f "$REPO_FILE" ] && [ -f "$HERMES_FILE" ]; then
    if cmp -s "$REPO_FILE" "$HERMES_FILE"; then
      echo "OK: $S"
    else
      echo "WARN: $S content differs (one side edited; reconcile via repo then re-deploy)"
    fi
  else
    if [ ! -f "$REPO_FILE" ]; then
      echo "ERROR: $S missing from repo scripts dir"
      RC=1
    fi
    if [ ! -f "$HERMES_FILE" ]; then
      echo "ERROR: $S missing from HERMES scripts dir"
      RC=1
    fi
  fi
done

if [ "$QUIET" -ne 1 ]; then
  for f in "$REPO_SCRIPTS"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if [ ! -e "$HERMES_SCRIPTS/$name" ]; then
      echo "INFO: repo-only: $name"
    fi
  done
  for f in "$HERMES_SCRIPTS"/*; do
    [ -f "$f" ] || continue
    name="$(basename "$f")"
    if [ ! -e "$REPO_SCRIPTS/$name" ]; then
      echo "INFO: local-only: $name"
    fi
  done
fi

exit "$RC"
