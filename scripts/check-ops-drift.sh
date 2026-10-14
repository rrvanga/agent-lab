#!/usr/bin/env bash
# Ops-script drift checker: reconcile cron-referenced scripts between the repo
# canonical copies (scripts/) and the deployed HERMES scripts dir.
#
# Plain runs are read-only — safe to run at any time. Emits one line per finding:
#   OK:     referenced script present & identical in both places
#   ERROR:  referenced script missing from the repo or HERMES side (exit 1)
#   WARN:   referenced script present but contents differ (exit 3)
#   INFO:   repo-only / local-only files (informational)
# Exit codes: 0 = clean; 1 = at least one ERROR; 2 = jobs.json missing,
# unreadable, or unparseable; 3 = content drift; 64 = usage error.
# Reconcile mode: --reconcile --toward=repo|deployed [--apply] plans changes by
# default and applies only content-drifted files when --apply is specified.
# Deps: bash, grep, python3 (json parsing — no jq required).
set -u

REPO_SCRIPTS="${REPO_SCRIPTS_DIR-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
HERMES_SCRIPTS="${HERMES_SCRIPTS_DIR-$HOME/.hermes/scripts}"
CRON_JOBS="${HERMES_CRON_JOBS:-$HOME/.hermes/cron/jobs.json}"

QUIET=0
RECONCILE=0
APPLY=0
TOWARD=""

usage() {
  cat <<'EOF'
Usage: check-ops-drift.sh [--quiet] [--help]
       check-ops-drift.sh --reconcile --toward=repo|deployed [--apply]

Exit codes:
  0   clean: no findings
  1   at least one ERROR (referenced script missing from one side)
  2   jobs.json missing, unreadable, or unparseable
  3   content drift present
  64  usage error

Examples:
  check-ops-drift.sh
  check-ops-drift.sh --reconcile --toward=deployed --apply
EOF
}

for arg in "$@"; do
  if [ "$arg" = "--help" ]; then
    usage
    exit 0
  fi
done

for arg in "$@"; do
  case "$arg" in
    --quiet) QUIET=1 ;;
    --reconcile) RECONCILE=1 ;;
    --apply) APPLY=1 ;;
    --toward=repo) TOWARD=repo ;;
    --toward=deployed) TOWARD=deployed ;;
    *) echo "Usage: check-ops-drift.sh [--quiet] [--help] or --reconcile --toward=repo|deployed [--apply]" >&2; exit 64 ;;
  esac
done

if [ "$APPLY" -eq 1 ] && [ "$RECONCILE" -ne 1 ]; then
  echo "Usage: check-ops-drift.sh [--quiet] [--help] or --reconcile --toward=repo|deployed [--apply]" >&2
  exit 64
fi
if [ "$RECONCILE" -eq 1 ] && [ -z "$TOWARD" ]; then
  echo "Usage: check-ops-drift.sh [--quiet] [--help] or --reconcile --toward=repo|deployed [--apply]" >&2
  exit 64
fi

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
DRIFT_COUNT=0
DRIFT_FILES=()
for S in "${CRON_SCRIPTS[@]:-}"; do
  [ -n "$S" ] || continue
  REPO_FILE="$REPO_SCRIPTS/$S"
  HERMES_FILE="$HERMES_SCRIPTS/$S"
  if [ -f "$REPO_FILE" ] && [ -f "$HERMES_FILE" ]; then
    if cmp -s "$REPO_FILE" "$HERMES_FILE"; then
      echo "OK: $S"
    else
      echo "WARN: $S content differs (one side edited; reconcile via repo then re-deploy)"
      echo "      fix: scripts/check-ops-drift.sh --reconcile --toward=repo --apply     # deployed copy -> repo"
      echo "      fix: scripts/check-ops-drift.sh --reconcile --toward=deployed --apply # repo -> deployed"
      DRIFT_FILES+=("$S")
      DRIFT_COUNT=$((DRIFT_COUNT + 1))
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

if [ "$RECONCILE" -eq 1 ]; then
  if [ "$DRIFT_COUNT" -eq 0 ]; then
    echo "INFO: no content drift; nothing to reconcile"
    exit 0
  fi
  if [ -z "$REPO_SCRIPTS" ] || [ -z "$HERMES_SCRIPTS" ]; then
    echo "ERROR: reconcile directories must not be empty" >&2
    exit 64
  fi
  REPO_RESOLVED="$(cd "$REPO_SCRIPTS" 2>/dev/null && pwd -P)" || { echo "ERROR: reconcile directories are invalid" >&2; exit 64; }
  HERMES_RESOLVED="$(cd "$HERMES_SCRIPTS" 2>/dev/null && pwd -P)" || { echo "ERROR: reconcile directories are invalid" >&2; exit 64; }
  if [ "$REPO_RESOLVED" = "/" ] || [ "$HERMES_RESOLVED" = "/" ]; then
    echo "ERROR: reconcile directories must not resolve to /" >&2
    exit 64
  fi
  for S in "${DRIFT_FILES[@]}"; do
    if [ "$TOWARD" = "deployed" ]; then
      SRC="$REPO_SCRIPTS/$S"
      DST="$HERMES_SCRIPTS/$S"
    else
      SRC="$HERMES_SCRIPTS/$S"
      DST="$REPO_SCRIPTS/$S"
    fi
    if [ "$APPLY" -eq 1 ]; then
      cp "$SRC" "$DST"
      echo "APPLIED: cp $SRC $DST"
    else
      echo "PLAN: cp $SRC $DST"
    fi
  done
  if [ "$APPLY" -eq 1 ]; then
    RESCAN_ARGS=()
    if [ "$QUIET" -eq 1 ]; then
      RESCAN_ARGS+=(--quiet)
    fi
    "$0" "${RESCAN_ARGS[@]}" >/dev/null 2>&1
    exit $?
  fi
  exit 0
fi

if [ "$RC" -eq 1 ]; then
  exit 1
elif [ "$DRIFT_COUNT" -gt 0 ]; then
  exit 3
fi
exit 0
