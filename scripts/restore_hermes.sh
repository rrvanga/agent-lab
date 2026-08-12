#!/usr/bin/env bash
# restore_hermes.sh — decrypt, verify and extract a Hermes backup.
#
# usage: restore_hermes.sh <backup-file> [dest-dir]
#
# With no dest-dir a scratch dir (mktemp -d) is used and the extraction is
# verified, so you can inspect the result without touching the live tree.
# Restoring to the live ~/.hermes is DESTRUCTIVE: stop the hermes-gateway
# service first. This script never issues any service-management command.
#
# Environment overrides:
#   PASSFILE  path to the gpg passphrase file  (default: $HOME/.config/hermes-backup/gpg-passphrase)
#   --passphrase-file <file> on the command line overrides it.

set -euo pipefail

PASSFILE="${PASSFILE:-$HOME/.config/hermes-backup/gpg-passphrase}"
DEST=""
BACKUP_FILE=""

usage() {
    printf 'usage: %s <backup-file> [dest-dir]\n' "$(basename "$0")"
}

for tool in gpg tar sqlite3 mktemp; do
    command -v "$tool" >/dev/null 2>&1 || { printf 'ERROR: required tool %s not found in PATH\n' "$tool"; exit 1; }
done

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

if [ "$#" -lt 1 ]; then
    usage >&2
    exit 2
fi
BACKUP_FILE="$1"
[ "$#" -ge 2 ] && DEST="$2"

printf 'WARNING: restoring is DESTRUCTIVE: it overwrites files in the destination.\n'
printf 'WARNING: for a full live restore, stop the hermes-gateway service first.\n'

[ -f "$BACKUP_FILE" ] || { printf 'ERROR: backup file not found: %s\n' "$BACKUP_FILE"; exit 1; }
[ -r "$BACKUP_FILE" ] || { printf 'ERROR: backup file not readable: %s\n' "$BACKUP_FILE"; exit 1; }
[ -f "$PASSFILE" ]    || { printf 'ERROR: passphrase file not found: %s (set PASSFILE or use --passphrase-file)\n' "$PASSFILE"; exit 1; }
[ -r "$PASSFILE" ]    || { printf 'ERROR: passphrase file not readable: %s\n' "$PASSFILE"; exit 1; }

if [ -z "$DEST" ]; then
    DEST="$(mktemp -d)"
    printf 'Using scratch restore dir: %s\n' "$DEST"
else
    mkdir -p "$DEST"
fi

# --- decrypt, verify, then extract (verify pass must succeed first) -----------
if ! gpg --batch --yes -d --passphrase-file "$PASSFILE" "$BACKUP_FILE" | tar -tz >/dev/null; then
    printf 'ERROR: could not decrypt/verify %s\n' "$BACKUP_FILE"
    exit 1
fi

if ! gpg --batch --yes -d --passphrase-file "$PASSFILE" "$BACKUP_FILE" | tar -xzf - -C "$DEST"; then
    printf 'ERROR: extraction into %s failed\n' "$DEST"
    exit 1
fi

printf 'Restored to: %s\n' "$DEST"

# --- prove the restore worked ------------------------------------------------
if [ -f "$DEST/.hermes/state.db" ]; then
    printf 'Restored state.db integrity: '
    sqlite3 "$DEST/.hermes/state.db" 'PRAGMA integrity_check;'
else
    printf 'WARNING: no .hermes/state.db found in archive %s\n' "$BACKUP_FILE"
fi
