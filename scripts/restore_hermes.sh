#!/usr/bin/env bash
# restore_hermes.sh — decrypt, verify and extract a Hermes backup.
#
# usage: restore_hermes.sh [--live|--yes] [--passphrase-file <file>] <backup-file> [dest-dir]
#
# With no dest-dir a scratch dir (mktemp -d) is used and the extraction is
# verified, so you can inspect the result without touching the live tree.
# Restoring to the live ~/.hermes is DESTRUCTIVE: pass --live (or --yes) and
# stop the hermes-gateway service first. This script never issues any
# service-management command.
#
# Archive layout is "<hermes-home-name>/..." (e.g. .hermes/config.yaml). If
# dest-dir is the hermes home itself — its basename matches the archive root,
# e.g. `restore_hermes.sh --live backup ... ~/.hermes` — the archive is
# extracted with --strip-components=1 so files land directly at live depth and
# actually overwrite the live config.yaml / state.db (a nesting assertion
# catches the old silent-failure mode). Otherwise the archive root prefix is
# preserved (scratch-dir inspection).
#
# Environment overrides:
#   PASSFILE  path to the gpg passphrase file  (default: $HOME/.config/hermes-backup/gpg-passphrase)
#   --passphrase-file <file> on the command line overrides it.

set -euo pipefail

PASSFILE="${PASSFILE:-$HOME/.config/hermes-backup/gpg-passphrase}"
DEST=""
BACKUP_FILE=""
LIVE_FLAG=0

usage() {
    printf 'usage: %s [--live|--yes] [--passphrase-file <file>] <backup-file> [dest-dir]\n' "$(basename "$0")"
}

for tool in gpg tar sqlite3 mktemp stat; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'ERROR: required tool %s not found in PATH\n' "$tool"; exit 1; }
done

# --- portable stat: GNU stat (-c %a) vs BSD stat (-f %Lp) --------------------
if stat -c %a / >/dev/null 2>&1; then
    STAT_MODE_FLAG='-c'
    STAT_MODE_FMT='%a'
else
    STAT_MODE_FLAG='-f'
    STAT_MODE_FMT='%Lp'
fi

# --- argument parsing ---------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --passphrase-file)
            if [ "$#" -lt 2 ]; then
                usage >&2
                exit 2
            fi
            PASSFILE="$2"
            shift 2
            ;;
        --live|--yes)
            LIVE_FLAG=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            usage >&2
            exit 2
            ;;
        *)
            break
            ;;
    esac
done

if [ "$#" -lt 1 ] || [ "$#" -gt 2 ]; then
    usage >&2
    exit 2
fi
BACKUP_FILE="$1"
DEST="${2:-}"

[ -f "$BACKUP_FILE" ] || { printf 'ERROR: backup file not found: %s\n' "$BACKUP_FILE"; exit 1; }
[ -r "$BACKUP_FILE" ] || { printf 'ERROR: backup file not readable: %s\n' "$BACKUP_FILE"; exit 1; }
[ -f "$PASSFILE" ]    || { printf 'ERROR: passphrase file not found: %s (set PASSFILE or use --passphrase-file)\n' "$PASSFILE"; exit 1; }
[ -s "$PASSFILE" ]    || { printf 'ERROR: passphrase file is empty: %s\n' "$PASSFILE"; exit 1; }
[ -r "$PASSFILE" ]    || { printf 'ERROR: passphrase file not readable: %s\n' "$PASSFILE"; exit 1; }
passfile_mode="$(stat "$STAT_MODE_FLAG" "$STAT_MODE_FMT" "$PASSFILE")" || { printf 'ERROR: could not stat passphrase file: %s\n' "$PASSFILE"; exit 1; }
[ "$passfile_mode" = 600 ] || { printf 'ERROR: passphrase file must be mode 600 (got %s): %s\n' "$passfile_mode" "$PASSFILE"; exit 1; }

if [ -z "$DEST" ]; then
    DEST="$(mktemp -d)" || { printf 'ERROR: could not create scratch dir\n'; exit 1; }
    printf 'Using scratch restore dir: %s\n' "$DEST"
else
    mkdir -p -- "$DEST" || { printf 'ERROR: could not create destination dir: %s\n' "$DEST"; exit 1; }
fi
# Resolve to an absolute canonical path so extraction and sidecar cleanup can
# never reach outside the destination.
DEST="$(cd "$DEST" && pwd -P)" || { printf 'ERROR: could not resolve destination dir: %s\n' "$DEST"; exit 1; }

# --- decrypt, verify, then extract (verify pass must succeed first) ----------
# Capture the listing so the archive root member can be inferred instead of
# hardcoding $DEST/.hermes/state.db.
if ! listing="$(gpg --batch --yes -d --passphrase-file "$PASSFILE" "$BACKUP_FILE" 2>/dev/null | tar -tz)"; then
    printf 'ERROR: could not decrypt/verify %s\n' "$BACKUP_FILE"
    exit 1
fi
ROOT="${listing%%$'\n'*}"
ROOT="${ROOT%/}"
[ -n "$ROOT" ] || { printf 'ERROR: archive %s lists no members\n' "$BACKUP_FILE"; exit 1; }

# --- validate every archive member stays inside the inferred root ------------
# Trusted-archive sanity check (not a security boundary): refuse members that
# are absolute paths or that escape the archive root (e.g. .. components).
validate_member() {
    local member="$1" comp c
    [ "${member#/}" = "$member" ] || return 1
    IFS=/ read -r -a comp <<< "$member"
    for c in "${comp[@]}"; do
        [ "$c" = ".." ] && return 1
    done
    case "$member" in
        "$ROOT"|"$ROOT"/*) return 0 ;;
    esac
    return 1
}

while IFS= read -r member; do
    [ -n "$member" ] || continue
    if ! validate_member "$member"; then
        printf 'ERROR: archive member %s escapes the archive root %s; refusing to extract\n' "$member" "$ROOT" >&2
        exit 1
    fi
done <<< "$listing"

# --- live restore requires an explicit flag ----------------------------------
LIVE=0
if [ "$(basename "$DEST")" = "$(basename "$ROOT")" ]; then
    if [ "$LIVE_FLAG" != 1 ]; then
        printf 'ERROR: %s looks like a live hermes home (basename %s matches archive root %s).\n' "$DEST" "$(basename "$DEST")" "$ROOT"
        printf 'ERROR: restoring over a live path is destructive; pass --live (or --yes) to proceed, after stopping the hermes-gateway service first.\n'
        exit 1
    fi
    LIVE=1
fi

if [ "$LIVE" = 1 ]; then
    printf 'WARNING: restoring over %s is DESTRUCTIVE: it overwrites files in the destination.\n' "$DEST"
    printf 'WARNING: stop the hermes-gateway service first for a clean restore.\n'
    printf 'Live restore detected: extracting archive root %s over %s with --strip-components=1\n' "$ROOT" "$DEST"
    # Stale sqlite WAL/SHM/journal sidecars could be replayed over the freshly
    # restored databases, so drop them before overwriting (exact paths inside
    # the canonical $DEST only — never outside it).
    for db in state.db kanban.db verification_evidence.db; do
        rm -f -- "$DEST/$db-wal" "$DEST/$db-shm" "$DEST/$db-journal"
    done
    if ! gpg --batch --yes -d --passphrase-file "$PASSFILE" "$BACKUP_FILE" 2>/dev/null | tar --strip-components=1 -xzf - --directory="$DEST"; then
        printf 'ERROR: extraction into %s failed\n' "$DEST"
        exit 1
    fi
    if [ -e "$DEST/$ROOT" ]; then
        printf 'ERROR: nested dir %s exists — the archive root did not land at live depth; live files were NOT overwritten\n' "$DEST/$ROOT"
        exit 1
    fi
    if [ ! -f "$DEST/config.yaml" ]; then
        printf 'ERROR: %s/config.yaml not found after live restore (expected archive root %s at live depth)\n' "$DEST" "$ROOT"
        exit 1
    fi
    restored_root="$DEST"
else
    if ! gpg --batch --yes -d --passphrase-file "$PASSFILE" "$BACKUP_FILE" 2>/dev/null | tar -xzf - --directory="$DEST"; then
        printf 'ERROR: extraction into %s failed\n' "$DEST"
        exit 1
    fi
    restored_root="$DEST/$ROOT"
    [ -f "$restored_root/config.yaml" ] || printf 'WARNING: no config.yaml at %s (unexpected archive layout)\n' "$restored_root"
fi

printf 'Restored to: %s\n' "$DEST"

# --- prove the restore worked ------------------------------------------------
dbs_found=0
for db in state.db kanban.db verification_evidence.db; do
    [ -f "$restored_root/$db" ] || continue
    dbs_found=1
    if out="$(sqlite3 "$restored_root/$db" ".timeout 5000" 'PRAGMA integrity_check;' 2>/dev/null)"; then
        printf '%s integrity: %s\n' "$db" "$out"
    else
        printf '%s integrity: FAILED (locked or corrupt)\n' "$db"
    fi
done
[ "$dbs_found" = 1 ] || printf 'WARNING: no databases found in archive %s\n' "$BACKUP_FILE"
