#!/usr/bin/env bash
# Ops-script drift checker: reconcile cron-referenced scripts between the repo
# canonical copies (scripts/) and the deployed HERMES scripts dir.
#
# Plain runs are read-only — safe to run at any time. Emits one line per finding:
#   OK:     referenced script present & identical in both places
#   ERROR:  referenced script missing from the repo or HERMES side (exit 1)
#   WARN:   referenced script present but contents differ (exit 3)
#   INFO:   repo-only / local-only files (informational)
# Exit codes: 0 = clean; 1 = at least one hard ERROR (which masks drift); 2 =
# jobs.json missing, unreadable, or unparseable; 3 = content drift; 64 = usage
# error.
# Reconcile mode: --reconcile --toward=repo|deployed [--apply] plans changes by
# default and applies only content-drifted files when --apply is specified. A
# reconcile with an ERROR exits 1; jobs.json errors still exit 2. PLAN: and
# APPLIED: lines are always printed, even under --quiet.
# `--toward=repo --apply` fails closed (exit 1, no files copied) if the git
# worktree containing $REPO_RESOLVED is dirty or its cleanliness cannot be
# verified; `--force` downgrades both to a WARN and continues.
# The cleanliness check covers $REPO_RESOLVED only (normally scripts/):
# uncommitted edits elsewhere in the repo are ignored, while any untracked file
# inside scripts/ counts as dirty.
# --quiet suppresses OK/INFO lines; WARN/ERROR lines are always printed.
# Deps: bash, grep, python3 (json parsing — no jq required).
set -u

TMP_DST=""
cleanup_tmp() {
  if [ -n "$TMP_DST" ]; then
    rm -f "$TMP_DST"
  fi
}
trap cleanup_tmp EXIT
trap 'cleanup_tmp; exit 130' INT
trap 'cleanup_tmp; exit 143' TERM
trap 'cleanup_tmp; exit 129' HUP

REPO_SCRIPTS="${REPO_SCRIPTS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
HERMES_SCRIPTS="${HERMES_SCRIPTS_DIR:-$HOME/.hermes/scripts}"
CRON_JOBS="${HERMES_CRON_JOBS:-$HOME/.hermes/cron/jobs.json}"

SELF_SOURCE="${BASH_SOURCE[0]-$0}"
case "$SELF_SOURCE" in
  */*) ;;
  *) SELF_SOURCE="$(command -v "$SELF_SOURCE" 2>/dev/null || printf '%s' "$0")" ;;
esac
SELF_PATH="$(cd "$(dirname "$SELF_SOURCE")" 2>/dev/null && pwd -P)/$(basename "$SELF_SOURCE")" || SELF_PATH="$0"

QUIET=0
RECONCILE=0
APPLY=0
FORCE=0
TOWARD=""

usage() {
  cat <<'EOF'
Usage: check-ops-drift.sh [--quiet] [--help]
       check-ops-drift.sh --reconcile --toward=repo|deployed [--apply] [--force]

Options:
  --quiet            suppress OK/INFO output (WARN/ERROR are still printed;
                     PLAN:/APPLIED: are always printed, even with --quiet)
  --force            allow --toward=repo --apply when the repo worktree is dirty
                     or its cleanliness cannot be verified

Cleanliness check scope: only $REPO_RESOLVED (normally scripts/) is checked.
Uncommitted edits elsewhere in the repo are ignored; any untracked file inside
that directory counts as dirty.

When run from the deployed copy, set REPO_SCRIPTS_DIR=/path/to/agent-lab/scripts.

Exit codes:
  0   clean: no findings
  1   at least one hard ERROR (masks content drift; reconcile also fails)
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
    --force) FORCE=1 ;;
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
if [ "$RECONCILE" -ne 1 ] && [ -n "$TOWARD" ]; then
  echo "Usage: check-ops-drift.sh [--quiet] [--help] or --reconcile --toward=repo|deployed [--apply]" >&2
  exit 64
fi
if [ "$FORCE" -eq 1 ] && \
   { [ "$RECONCILE" -ne 1 ] || [ "$APPLY" -ne 1 ] || [ "$TOWARD" != "repo" ]; }; then
  echo "Usage: check-ops-drift.sh [--quiet] [--help] or --reconcile --toward=repo|deployed [--apply]" >&2
  exit 64
fi

if [ -z "$REPO_SCRIPTS" ] || [ -z "$HERMES_SCRIPTS" ] || \
   [ ! -d "$REPO_SCRIPTS" ] || [ ! -d "$HERMES_SCRIPTS" ]; then
  echo "ERROR: script directories must be non-empty existing directories" >&2
  exit 64
fi
REPO_RESOLVED="$(cd "$REPO_SCRIPTS" 2>/dev/null && pwd -P)" || { echo "ERROR: invalid repo scripts directory" >&2; exit 64; }
HERMES_RESOLVED="$(cd "$HERMES_SCRIPTS" 2>/dev/null && pwd -P)" || { echo "ERROR: invalid HERMES scripts directory" >&2; exit 64; }
if [ "$REPO_RESOLVED" = "/" ] || [ "$HERMES_RESOLVED" = "/" ]; then
  echo "ERROR: script directories must not resolve to /" >&2
  exit 64
fi

if [ ! -r "$CRON_JOBS" ]; then
  echo "ERROR: jobs.json not found or unreadable at: $CRON_JOBS" >&2
  exit 2
fi

PY_OUTPUT="$(python3 - "$CRON_JOBS" <<'PYEOF'
import json, sys

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
                names.add(value)
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

CRON_SCRIPTS=()
if [ -n "$PY_OUTPUT" ]; then
  mapfile -t CRON_SCRIPTS <<< "$PY_OUTPUT"
fi

RC=0
DRIFT_COUNT=0
DRIFT_FILES=()
if [ "${#CRON_SCRIPTS[@]}" -gt 0 ]; then
  for S in "${CRON_SCRIPTS[@]:-}"; do
    if ! [[ "$S" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$S" = .* ]] || [[ "$S" = */* ]]; then
      echo "ERROR: unsafe script name '$S' in $CRON_JOBS" >&2
      RC=1
      continue
    fi
    REPO_FILE="$REPO_SCRIPTS/$S"
    HERMES_FILE="$HERMES_SCRIPTS/$S"
    if [ -f "$REPO_FILE" ] && [ -f "$HERMES_FILE" ]; then
      cmp -s "$REPO_FILE" "$HERMES_FILE"
      CMP_RC=$?
      if [ "$CMP_RC" -eq 0 ]; then
        if [ "$QUIET" -eq 0 ]; then
          echo "OK: $S"
        fi
      elif [ "$CMP_RC" -ge 2 ]; then
        echo "ERROR: cannot compare $REPO_FILE and $HERMES_FILE (cmp exit $CMP_RC)"
        RC=1
      else
        echo "WARN: $S content differs (one side edited; reconcile via repo then re-deploy)"
        echo "      fix: $SELF_PATH --reconcile --toward=repo --apply     # deployed copy -> repo"
        echo "      fix: $SELF_PATH --reconcile --toward=deployed --apply # repo -> deployed"
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
fi

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
  if [ "$RC" -ne 0 ]; then
    exit 1
  fi
  if [ "$DRIFT_COUNT" -eq 0 ]; then
    if [ "$QUIET" -ne 1 ]; then
      echo "INFO: no content drift; nothing to reconcile"
    fi
    exit 0
  fi
  if [ "$TOWARD" = "repo" ] && [ "$APPLY" -eq 1 ]; then
    GIT_CHECK="$(git -C "$REPO_RESOLVED" rev-parse --is-inside-work-tree 2>&1)"
    GIT_RC=$?
    GIT_ERR_FIRST="${GIT_CHECK%%$'\n'*}"
    if [ "$GIT_RC" -ne 0 ] || [ "$GIT_CHECK" != "true" ]; then
      if [ "$GIT_RC" -eq 127 ]; then
        GIT_CAUSE="git unavailable"
        GIT_DETAIL="${GIT_ERR_FIRST:-no output from git}"
      elif [ "$GIT_RC" -eq 0 ] || [[ "$GIT_ERR_FIRST" == *"not a git repository"* ]]; then
        GIT_CAUSE="not a git work tree"
        GIT_DETAIL="${GIT_ERR_FIRST:-git reported not a work tree}"
      else
        GIT_CAUSE="git rev-parse failed"
        GIT_DETAIL="${GIT_ERR_FIRST:-no output from git}"
      fi
      if [ "$FORCE" -eq 1 ]; then
        echo "WARN: cannot verify repo worktree cleanliness ($GIT_CAUSE): $REPO_RESOLVED: $GIT_DETAIL (continuing because --force was given)" >&2
      else
        echo "ERROR: cannot verify repo worktree cleanliness ($GIT_CAUSE): $REPO_RESOLVED: $GIT_DETAIL" >&2
        echo "ERROR: cannot verify repo worktree cleanliness ($GIT_CAUSE): $REPO_RESOLVED: $GIT_DETAIL"
        exit 1
      fi
    else
      GIT_STATUS="$(git -C "$REPO_RESOLVED" status --porcelain 2>&1)"
      GIT_RC=$?
      if [ "$GIT_RC" -ne 0 ]; then
        GIT_ERR_FIRST="${GIT_STATUS%%$'\n'*}"
        GIT_DETAIL="${GIT_ERR_FIRST:-no output from git}"
        if [ "$FORCE" -eq 1 ]; then
          echo "WARN: cannot verify repo worktree cleanliness (git status failed): $REPO_RESOLVED: $GIT_DETAIL (continuing because --force was given)" >&2
        else
          echo "ERROR: cannot verify repo worktree cleanliness (git status failed): $REPO_RESOLVED: $GIT_DETAIL" >&2
          echo "ERROR: cannot verify repo worktree cleanliness (git status failed): $REPO_RESOLVED: $GIT_DETAIL"
          exit 1
        fi
      elif [ -n "$GIT_STATUS" ]; then
        if [ "$FORCE" -eq 1 ]; then
          echo "WARN: repo worktree is dirty: $REPO_RESOLVED (continuing because --force was given)" >&2
        else
          DIRTY_LINES=()
          while IFS= read -r line; do
            [ -n "$line" ] && DIRTY_LINES+=("$line")
          done <<< "$GIT_STATUS"
          DIRTY_SHOWN=0
          for line in "${DIRTY_LINES[@]}"; do
            if [ "$DIRTY_SHOWN" -ge 10 ]; then
              break
            fi
            echo "       $line"
            DIRTY_SHOWN=$((DIRTY_SHOWN + 1))
          done
          if [ "${#DIRTY_LINES[@]}" -gt 10 ]; then
            echo "       ... $((${#DIRTY_LINES[@]} - 10)) more"
          fi
          echo "ERROR: repo worktree is dirty: $REPO_RESOLVED; commit or stash first, or pass --force" >&2
          echo "ERROR: repo worktree is dirty: $REPO_RESOLVED; commit or stash first, or pass --force"
          exit 1
        fi
      fi
    fi
  fi

  # Validate every pending write before touching anything so a bad entry cannot
  # leave a half-applied pair behind.
  if [ "$APPLY" -eq 1 ]; then
    VALIDATION_ERRORS=0
    for S in "${DRIFT_FILES[@]:-}"; do
      if ! [[ "$S" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$S" = .* ]] || [[ "$S" = */* ]]; then
        echo "ERROR: unsafe script name '$S' in $CRON_JOBS" >&2
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
        continue
      fi
      if [ "$TOWARD" = "deployed" ]; then
        SRC="$REPO_SCRIPTS/$S"
        DST="$HERMES_SCRIPTS/$S"
      else
        SRC="$HERMES_SCRIPTS/$S"
        DST="$REPO_SCRIPTS/$S"
      fi
      if [ ! -r "$SRC" ]; then
        echo "ERROR: source not readable: $SRC" >&2
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      fi
      if [ -L "$DST" ]; then
        echo "ERROR: refusing to write through symlink $DST" >&2
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      fi
      DST_DIR="$(dirname "$DST")"
      if [ ! -d "$DST_DIR" ]; then
        echo "ERROR: destination directory does not exist: $DST_DIR" >&2
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      elif [ ! -w "$DST_DIR" ]; then
        echo "ERROR: destination directory is not writable: $DST_DIR" >&2
        VALIDATION_ERRORS=$((VALIDATION_ERRORS + 1))
      fi
    done
    if [ "$VALIDATION_ERRORS" -ne 0 ]; then
      exit 1
    fi
  fi

  for S in "${DRIFT_FILES[@]:-}"; do
    if ! [[ "$S" =~ ^[A-Za-z0-9._-]+$ ]] || [[ "$S" = .* ]] || [[ "$S" = */* ]]; then
      echo "ERROR: unsafe script name '$S' in $CRON_JOBS" >&2
      exit 1
    fi
    if [ "$TOWARD" = "deployed" ]; then
      SRC="$REPO_SCRIPTS/$S"
      DST="$HERMES_SCRIPTS/$S"
    else
      SRC="$HERMES_SCRIPTS/$S"
      DST="$REPO_SCRIPTS/$S"
    fi
    if [ -L "$DST" ]; then
      echo "ERROR: refusing to write through symlink $DST" >&2
      exit 1
    fi
    if [ "$APPLY" -eq 1 ]; then
      TMP_DST="$DST.tmp.$$"
      if ! cp -p "$SRC" "$TMP_DST" || ! mv -f "$TMP_DST" "$DST"; then
        rm -f "$TMP_DST"
        echo "ERROR: failed to copy $SRC -> $DST" >&2
        exit 1
      fi
      TMP_DST=""
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
    if [ "${#RESCAN_ARGS[@]}" -gt 0 ]; then
      RESCAN_OUTPUT="$("$SELF_PATH" "${RESCAN_ARGS[@]:-}" 2>&1)"
    else
      RESCAN_OUTPUT="$("$SELF_PATH" 2>&1)"
    fi
    RESCAN_RC=$?
    if [ "$RESCAN_RC" -ne 0 ]; then
      printf '%s\n' "$RESCAN_OUTPUT"
    fi
    exit "$RESCAN_RC"
  fi
  exit 0
fi

if [ "$RC" -ne 0 ]; then
  exit 1
elif [ "$DRIFT_COUNT" -gt 0 ]; then
  exit 3
fi
exit 0
