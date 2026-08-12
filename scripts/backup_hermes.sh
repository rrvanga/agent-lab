#!/usr/bin/env bash
# backup_hermes.sh — crash-safe, encrypted daily backup of the Hermes agent home.
#
# Produces BACKUP_DIR/hermes-backup-YYYYMMDD_HHMMSS.tar.gz.gpg containing a
# consistent snapshot of ~/.hermes (state.db / kanban.db / verification_evidence.db
# are snapshotted via the sqlite online backup API while the gateway is live),
# encrypted with gpg AES256 before it ever touches disk.
#
# Cron contract: stdout is delivered verbatim. On success exactly one short
# summary line is printed; on failure a clear error is printed (also to stderr)
# and the exit status is non-zero.
#
# Environment overrides:
#   HERMES_HOME  path to the hermes home           (default: $HOME/.hermes)
#   BACKUP_DIR   where backups are written         (default: $HOME/.hermes-backups)
#   PASSFILE     path to the gpg passphrase file   (default: $HOME/.config/hermes-backup/gpg-passphrase)
#   RETENTION    number of backups to keep         (default: 14)

set -euo pipefail

HERMES_HOME="${HERMES_HOME:-$HOME/.hermes}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/.hermes-backups}"
PASSFILE="${PASSFILE:-$HOME/.config/hermes-backup/gpg-passphrase}"
RETENTION="${RETENTION:-14}"

die() {
    printf 'ERROR: %s\n' "$*" >&2
    printf 'ERROR: %s\n' "$*"
    exit 1
}

# --- prerequisite checks (fail loudly, no partial work) ---------------------
for tool in tar gzip gpg sqlite3 mktemp stat date; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' not found in PATH"
done

[ -d "$HERMES_HOME" ] || die "hermes home not found: $HERMES_HOME"
[ -f "$PASSFILE" ]    || die "passphrase file not found: $PASSFILE (create it or set PASSFILE)"
[ -s "$PASSFILE" ]    || die "passphrase file is empty: $PASSFILE"
[ -r "$PASSFILE" ]    || die "passphrase file not readable: $PASSFILE"
[ "$RETENTION" -ge 1 ] 2>/dev/null || die "RETENTION must be a positive integer (got '$RETENTION')"

mkdir -p "$BACKUP_DIR"
chmod 700 "$BACKUP_DIR"

# --- live integrity probe (warn only, never abort) --------------------------
WARN=""
if state_integrity="$(sqlite3 "$HERMES_HOME/state.db" 'PRAGMA integrity_check;' 2>/dev/null)"; then
    if [ "$state_integrity" != "ok" ]; then
        WARN=" WARN: state.db integrity"
    fi
else
    WARN=" WARN: state.db integrity"
fi

# --- consistent snapshot of the live sqlite databases -----------------------
# The gateway writes state.db / kanban.db / verification_evidence.db while
# running, so tar must never read them directly. sqlite .backup uses the online
# backup API and yields a consistent copy; the copies land in a throwaway dir
# that is removed on exit.
WORK="$(mktemp -d)"
trap 'rm -rf -- "$WORK"' EXIT

snap_files=(state.db kanban.db verification_evidence.db)
snap_operands=()
for db in "${snap_files[@]}"; do
    if [ -f "$HERMES_HOME/$db" ]; then
        sqlite3 "$HERMES_HOME/$db" ".backup '$WORK/$db'" || die "sqlite .backup failed for $db"
        snap_operands+=("$db")
    fi
done

# --- assemble the tarball -----------------------------------------------------
# Operate from the parent of HERMES_HOME so members are "$HERMES_NAME/..."
# (e.g. .hermes/config.yaml) and a restore yields a tree containing .hermes/.
HERMES_NAME="$(basename "$HERMES_HOME")"
HERMES_PARENT="$(dirname "$HERMES_HOME")"

excludes=(
    --exclude="$HERMES_NAME/hermes-agent"
    --exclude="$HERMES_NAME/bin"
    --exclude="$HERMES_NAME/cache"
    --exclude="$HERMES_NAME/audio_cache"
    --exclude="$HERMES_NAME/image_cache"
    --exclude="$HERMES_NAME/images"
    --exclude="$HERMES_NAME/__pycache__"
    --exclude="$HERMES_NAME/gateway.pid"
    --exclude="$HERMES_NAME/gateway_state.json"
    --exclude="$HERMES_NAME/.hermes_history"
    --exclude='*.pyc'
    --exclude='*.lock'
    --exclude='*.db-wal'
    --exclude='*.db-shm'
    --exclude="$HERMES_NAME/state.db"
    --exclude="$HERMES_NAME/kanban.db"
    --exclude="$HERMES_NAME/verification_evidence.db"
)

# Rewrite the snapshot names so they appear at their original in-tree location.
transform="s|^state\.db$|$HERMES_NAME/state.db|;s|^kanban\.db$|$HERMES_NAME/kanban.db|;s|^verification_evidence\.db$|$HERMES_NAME/verification_evidence.db|"

tar_args=(czf - "${excludes[@]}" --transform="$transform" -C "$HERMES_PARENT" "$HERMES_NAME")
if [ "${#snap_operands[@]}" -gt 0 ]; then
    tar_args+=(-C "$WORK" "${snap_operands[@]}")
fi

# --- encrypt BEFORE touching disk -------------------------------------------
TIMESTAMP="$(date +%Y%m%d_%H%M%S)"
NEW="hermes-backup-$TIMESTAMP.tar.gz.gpg"
TMPOUT="$BACKUP_DIR/.incomplete-$TIMESTAMP-$$.gpg"

if ! tar "${tar_args[@]}" | gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSFILE" --output "$TMPOUT"; then
    rm -f -- "$TMPOUT"
    die "backup creation failed (tar/gpg error)"
fi

# --- verify the NEW backup BEFORE pruning anything ---------------------------
if ! gpg --batch --yes -d --passphrase-file "$PASSFILE" "$TMPOUT" | tar -tz >/dev/null; then
    rm -f -- "$TMPOUT"
    die "integrity verification of the new backup failed; nothing written, nothing pruned"
fi

mv -- "$TMPOUT" "$BACKUP_DIR/$NEW"

# --- retention: keep the 14 most recent, delete older ------------------------
shopt -s nullglob
existing=("$BACKUP_DIR"/hermes-backup-*.tar.gz.gpg)
if [ "${#existing[@]}" -gt "$RETENTION" ]; then
    remove_count=$(( ${#existing[@]} - RETENTION ))
    rm -f -- "${existing[@]:0:$remove_count}"
    existing=("$BACKUP_DIR"/hermes-backup-*.tar.gz.gpg)
fi

BYTES="$(stat -c %s "$BACKUP_DIR/$NEW")"
SIZE_MB="$(awk -v b="$BYTES" 'BEGIN { printf "%.1f", b / 1048576 }')"

printf 'backup OK: %s (%s MB, %d kept)%s\n' "$NEW" "$SIZE_MB" "${#existing[@]}" "$WARN"
