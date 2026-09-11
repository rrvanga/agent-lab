#!/usr/bin/env bash
# Test harness for scripts/check-ops-drift.sh. Builds a fake repo scripts dir,
# fake HERMES home (scripts + cron/jobs.json), and asserts drift behaviour.
# Run from anywhere: bash scripts/test-check-ops-drift.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECKER="$SCRIPT_DIR/check-ops-drift.sh"

PASSED=0
FAILURES=0

pass() { PASSED=$((PASSED + 1)); echo "PASS: $1"; }
fail() { FAILURES=$((FAILURES + 1)); echo "FAIL: $1"; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

REPO="$TMP/repo/scripts"
FAKEHOME="$TMP/fakehome"
HERMES_SCRIPTS="$FAKEHOME/scripts"
CRON_DIR="$FAKEHOME/cron"
mkdir -p "$REPO" "$HERMES_SCRIPTS" "$CRON_DIR"

FIX_OK="fixture_ok.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo ok' > "$REPO/$FIX_OK"
printf '%s\n' '#!/usr/bin/env bash' 'echo ok' > "$HERMES_SCRIPTS/$FIX_OK"

write_jobs() {
  printf '%s' "$1" > "$CRON_DIR/jobs.json"
}

run_checker() {
  set +e
  HERMES_SCRIPTS_DIR="$HERMES_SCRIPTS" \
  HERMES_CRON_JOBS="$CRON_DIR/jobs.json" \
  REPO_SCRIPTS_DIR="$REPO" \
    "$CHECKER" "$@" 2>&1
  local rc=$?
  set -e
  return "$rc"
}

capture() {
  set +e
  OUT="$(run_checker "$@")"
  RC=$?
  set -e
}

# --- scenario A: everything matches ----------------------------------------
write_jobs '[{"script": "fixture_ok.sh"}]'
capture
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "OK: $FIX_OK"; then
  pass "matching script -> OK: + exit 0"
else
  fail "matching script -> OK: + exit 0 (rc=$RC, out=$OUT)"
fi

# --- scenario B: script missing from repo side ------------------------------
write_jobs '[{"script": "fixture_ok.sh"}, {"script": "missing_repo.sh"}]'
printf '%s\n' '#!/usr/bin/env bash' 'echo present-here-only' > "$HERMES_SCRIPTS/missing_repo.sh"
capture
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "ERROR: missing_repo.sh missing from repo scripts dir"; then
  pass "script missing from repo -> ERROR: + exit 1"
else
  fail "script missing from repo -> ERROR: + exit 1 (rc=$RC, out=$OUT)"
fi

# --- scenario C: script missing from HERMES side ----------------------------
write_jobs '[{"script": "fixture_ok.sh"}, {"script": "missing_local.sh"}]'
printf '%s\n' '#!/usr/bin/env bash' 'echo repo-only-here' > "$REPO/missing_local.sh"
capture
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "ERROR: missing_local.sh missing from HERMES scripts dir"; then
  pass "script missing from HERMES -> ERROR: + exit 1"
else
  fail "script missing from HERMES -> ERROR: + exit 1 (rc=$RC, out=$OUT)"
fi

# --- scenario D: content differs -> WARN:, exit 0 ---------------------------
write_jobs '[{"script": "fixture_diff.sh"}]'
printf '%s\n' '#!/usr/bin/env bash' 'echo v1' > "$REPO/fixture_diff.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo v2' > "$HERMES_SCRIPTS/fixture_diff.sh"
capture
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "WARN: fixture_diff.sh content differs"; then
  pass "content diff -> WARN: + exit 0"
else
  fail "content diff -> WARN: + exit 0 (rc=$RC, out=$OUT)"
fi

# --- scenario E: --quiet suppresses INFO lines ------------------------------
capture --quiet
if printf '%s' "$OUT" | grep -q "^INFO:"; then
  fail "--quiet suppresses INFO lines (out=$OUT)"
else
  pass "--quiet suppresses INFO lines"
fi

# --- scenario F: unreadable jobs.json -> exit 2 -----------------------------
rm "$CRON_DIR/jobs.json"
capture
if [ "$RC" -eq 2 ]; then
  pass "missing jobs.json -> exit 2"
else
  fail "missing jobs.json -> exit 2 (rc=$RC, out=$OUT)"
fi

echo
echo "$PASSED passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
