#!/usr/bin/env bash
# DEPRECATED 2026-09-04 — superseded by Hermes built-in `hermes backup -q -l daily`
# (cron job daily-hermes-backup, 06:30; snapshots in ~/.hermes/state-snapshots/,
# restore via in-session `/snapshot restore <id>`). Kept for history; see docs/backup.md.
# backup_hermes.sh — crash-safe, encrypted daily backup of the Hermes agent home.
#
# Produces BACKUP_DIR/hermes-backup-YYYYMMDD_HHMMSS.tar.gz.gpg (UTC timestamps)
# containing a consistent snapshot of ~/.hermes (state.db / kanban.db /
# verification_evidence.db are snapshotted via the sqlite online backup API while
# the gateway is live, with a 15s busy timeout so a busy database waits instead
# of dying), encrypted with gpg AES256 before it ever touches disk.
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
for tool in tar gzip gpg sqlite3 mktemp stat date awk flock; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool '$tool' not found in PATH"
done

# --- portable stat: GNU stat (-c %a) vs BSD stat (-f %Lp) --------------------
if stat -c %a / >/dev/null 2>&1; then
    STAT_MODE_FLAG='-c'
    STAT_MODE_FMT='%a'
    STAT_SIZE_FMT='%s'
else
    STAT_MODE_FLAG='-f'
    STAT_MODE_FMT='%Lp'
    STAT_SIZE_FMT='%z'
fi

[ -d "$HERMES_HOME" ] || die "hermes home not found: $HERMES_HOME"
[ -f "$PASSFILE" ]    || die "passphrase file not found: $PASSFILE (create it or set PASSFILE)"
[ -s "$PASSFILE" ]    || die "passphrase file is empty: $PASSFILE"
[ -r "$PASSFILE" ]    || die "passphrase file not readable: $PASSFILE"
passfile_mode="$(stat "$STAT_MODE_FLAG" "$STAT_MODE_FMT" "$PASSFILE")" || die "could not stat passphrase file: $PASSFILE"
[ "$passfile_mode" = 600 ] || die "passphrase file must be mode 600 (got $passfile_mode): $PASSFILE"
[ "$RETENTION" -ge 1 ] 2>/dev/null || die "RETENTION must be a positive integer (got '$RETENTION')"

mkdir -p -- "$BACKUP_DIR"  || die "could not create backup dir: $BACKUP_DIR"
chmod 700 -- "$BACKUP_DIR" || die "could not chmod 700 backup dir: $BACKUP_DIR"

# --- concurrency lock: refuse concurrent runs instead of racing --------------
if ! exec 9>"$BACKUP_DIR/.lock"; then
    die "could not create lock file: $BACKUP_DIR/.lock"
fi
flock -n 9 || die "another backup run is in progress (lock held: $BACKUP_DIR/.lock)"

# --- sweep stale incomplete files (>1 day) -----------------------------------
find "$BACKUP_DIR" -maxdepth 1 -name '.incomplete-*' -mtime +1 -delete 2>/dev/null || true

# --- live integrity probe (warn only, never abort) ---------------------------
snap_files=(state.db kanban.db verification_evidence.db)
WARN=""
for db in "${snap_files[@]}"; do
    if [ -f "$HERMES_HOME/$db" ]; then
        if state_integrity="$(sqlite3 "$HERMES_HOME/$db" ".timeout 5000" 'PRAGMA integrity_check;' 2>/dev/null)"; then
            [ "$state_integrity" = "ok" ] || WARN="${WARN} WARN: $db integrity"
        else
            WARN="${WARN} WARN: $db integrity"
        fi
    fi
done

# --- consistent snapshot of the live sqlite databases -----------------------
# The gateway writes state.db / kanban.db / verification_evidence.db while
# running, so tar must never read them directly. sqlite .backup uses the online
# backup API and yields a consistent copy; the copies land in a throwaway dir on
# real disk under BACKUP_DIR (not /tmp, which may be tmpfs/RAM) and are removed
# on exit.
WORK="$(mktemp -d "$BACKUP_DIR/.snap.XXXXXX")" || die "could not create snapshot dir under $BACKUP_DIR"
trap 'rm -rf -- "$WORK"' EXIT

snap_operands=()
for db in "${snap_files[@]}"; do
    if [ -f "$HERMES_HOME/$db" ]; then
        sqlite3 "$HERMES_HOME/$db" ".timeout 15000" ".backup '$WORK/$db'" || die "sqlite .backup failed for $db"
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
    --exclude='*.db-journal'
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
TIMESTAMP="$(date -u +%Y%m%d_%H%M%S)"
NEW="hermes-backup-$TIMESTAMP.tar.gz.gpg"
TMPOUT="$BACKUP_DIR/.incomplete-$TIMESTAMP-$$.gpg"

# GNU tar exits 1 when a file changed while being read — expected on a LIVE
# ~/.hermes (the gateway + cron ticker write constantly). Treat only tar rc>=2
# (fatal) or a gpg failure as a real error; suppress the benign stderr noise.
set +e
tar "${tar_args[@]}" 2> >(grep -v 'file changed as we read it' >&2) | \
        gpg --batch --yes --symmetric --cipher-algo AES256 \
        --passphrase-file "$PASSFILE" --output "$TMPOUT"
rcs=("${PIPESTATUS[@]}")
set -e
tar_rc="${rcs[0]:-2}"
gpg_rc="${rcs[1]:-2}"
if [ "$gpg_rc" -ne 0 ] || [ "$tar_rc" -ge 2 ]; then
    rm -f -- "$TMPOUT"
    die "backup creation failed (tar rc=$tar_rc, gpg rc=$gpg_rc)"
fi

# --- verify the NEW backup BEFORE pruning anything ---------------------------
if ! gpg --batch --yes -d --passphrase-file "$PASSFILE" "$TMPOUT" 2>/dev/null | tar -tz >/dev/null; then
    rm -f -- "$TMPOUT"
    die "integrity verification of the new backup failed; nothing written, nothing pruned"
fi

mv -- "$TMPOUT" "$BACKUP_DIR/$NEW"

# --- retention: keep the 14 most recent, delete older ------------------------
shopt -s nullglob
existing=("$BACKUP_DIR"/hermes-backup-*.tar.gz.gpg)
if [ "${#existing[@]}" -gt "$RETENTION" ]; then
    remove_count=$(( ${#existing[@]} - RETENTION ))
    rm -f -- "${existing[@]:0:$remove_count}" || die "retention prune failed (new backup $NEW is safe)"
    existing=("$BACKUP_DIR"/hermes-backup-*.tar.gz.gpg)
fi

BYTES="$(stat "$STAT_MODE_FLAG" "$STAT_SIZE_FMT" "$BACKUP_DIR/$NEW")"
SIZE_MB="$(awk -v b="$BYTES" 'BEGIN { printf "%.1f", b / 1048576 }')"

printf 'backup OK: %s (%s MB, %d kept)%s\n' "$NEW" "$SIZE_MB" "${#existing[@]}" "$WARN"
