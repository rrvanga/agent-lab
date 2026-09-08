#!/usr/bin/env bash
# Daily quick snapshot via Hermes' built-in `hermes backup -q`.
# 2026-09-04 — replaces the agent-lab encrypted backup_hermes.sh (retired).
#
# Built-in semantics (v0.21): `-q` writes a LABELED SNAPSHOT DIR under
# ~/.hermes/state-snapshots/<UTCts>-<label>/ — not a zip file; `-o` is
# ignored when `-q` is set. Restore: /snapshot restore <id> (in-session).
#
# Retention: the built-in auto-prunes globally (keep=20, rmtree). This wrapper
# additionally keeps only the newest 14 *-daily snapshots (rm -rf rotation —
# lifecycle pruning, not interactive disposal; pattern is exact, pre-update
# and other labels are never touched).
#
# no_agent cron contract: non-empty stdout is delivered verbatim; rc!=0 alerts.
# User preference (2026-09-05): SILENT ON SUCCESS — empty stdout on the happy
# path; clear message + non-zero exit on failure. No "ok" chatter in chat.

set -u

HERMES_BIN="$HOME/.hermes/hermes-agent/venv/bin/hermes"
SNAP_ROOT="$HOME/.hermes/state-snapshots"
LABEL="daily"
KEEP_DAILY=14

if [ ! -x "$HERMES_BIN" ]; then
  echo "daily-hermes-backup FAILED: hermes binary missing at $HERMES_BIN"
  exit 1
fi

OUT="$("$HERMES_BIN" backup -q -l "$LABEL" 2>&1)" || {
  rc=$?
  echo "daily-hermes-backup FAILED (hermes backup exit $rc):"
  echo "$OUT"
  exit 1
}

NEWEST="$(ls -1dt "$SNAP_ROOT"/*-"$LABEL" 2>/dev/null | head -1)"
if [ -z "$NEWEST" ] || [ ! -d "$NEWEST" ]; then
  echo "daily-hermes-backup FAILED: no $LABEL snapshot appeared under $SNAP_ROOT"
  echo "$OUT"
  exit 1
fi

ID="$(basename "$NEWEST")"
SIZE="$(du -sh "$NEWEST" | cut -f1)"

# retention: keep the newest KEEP_DAILY daily snapshots
shopt -s nullglob
mapfile -t OLD < <(ls -1dt "$SNAP_ROOT"/*-"$LABEL" | tail -n +$((KEEP_DAILY + 1)))
PRUNED=0
for d in "${OLD[@]:-}"; do
  [ -d "$d" ] && rm -rf -- "$d" && PRUNED=$((PRUNED + 1))
done

# Success path: SILENT (empty stdout) — cron delivers nothing on normal runs;
# failures print above and exit 1. Audit trail: scheduler last_status +
# snapshot-dir presence (dormancy still visible in `hermes cron list`).
# VERBOSE=1 restores the ok line for manual runs:
if [ "${VERBOSE:-0}" = "1" ]; then
  echo "daily-hermes-backup ok: $ID ($SIZE); pruned $PRUNED old daily (keep $KEEP_DAILY)"
  echo "restore: /snapshot restore $ID"
fi