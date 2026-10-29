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

# --- scenario D: content differs -> WARN:, exit 3 ---------------------------
write_jobs '[{"script": "fixture_diff.sh"}]'
printf '%s\n' '#!/usr/bin/env bash' 'echo v1' > "$REPO/fixture_diff.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo v2' > "$HERMES_SCRIPTS/fixture_diff.sh"
capture
if [ "$RC" -eq 3 ] && printf '%s' "$OUT" | grep -q "WARN: fixture_diff.sh content differs" \
     && printf '%s' "$OUT" | grep -q "fix: .* --reconcile"; then
  pass "content diff -> WARN: + fix: + exit 3"
else
  fail "content diff -> WARN: + fix: + exit 3 (rc=$RC, out=$OUT)"
fi

# --- scenario E: --quiet suppresses INFO lines ------------------------------
capture --quiet
if printf '%s' "$OUT" | grep -q "^INFO:"; then
  fail "--quiet suppresses INFO lines (out=$OUT)"
else
  pass "--quiet suppresses INFO lines"
fi

# --- scenario G: --help -> exit 0 and documents exit codes -------------------
capture --help
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "3   content drift"; then
  pass "--help -> exit 0 + exit-code table"
else
  fail "--help -> exit 0 + exit-code table (rc=$RC, out=$OUT)"
fi

# --- scenario H: reconcile requires an explicit direction -------------------
write_jobs '[{"script": "fixture_diff.sh"}]'
repo_before="$(<"$REPO/fixture_diff.sh")"
hermes_before="$(<"$HERMES_SCRIPTS/fixture_diff.sh")"
capture --reconcile
if [ "$RC" -eq 64 ] && [ "$(<"$REPO/fixture_diff.sh")" = "$repo_before" ] \
    && [ "$(<"$HERMES_SCRIPTS/fixture_diff.sh")" = "$hermes_before" ]; then
  pass "reconcile without --toward -> exit 64 + unchanged fixtures"
else
  fail "reconcile without --toward -> exit 64 + unchanged fixtures (rc=$RC, out=$OUT)"
fi

# --- scenario I: reconcile repo dry run --------------------------------------
capture --reconcile --toward=repo
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "PLAN: cp $HERMES_SCRIPTS/fixture_diff.sh $REPO/fixture_diff.sh" \
    && ! cmp -s "$REPO/fixture_diff.sh" "$HERMES_SCRIPTS/fixture_diff.sh" \
    && grep -q 'v1' "$REPO/fixture_diff.sh"; then
  pass "reconcile toward repo dry run -> repo PLAN: + unchanged repo"
else
  fail "reconcile toward repo dry run -> repo PLAN: + unchanged repo (rc=$RC, out=$OUT)"
fi

# --- scenario J: reconcile deployed apply -----------------------------------
capture --reconcile --toward=deployed --apply
if [ "$RC" -eq 0 ] && cmp -s "$REPO/fixture_diff.sh" "$HERMES_SCRIPTS/fixture_diff.sh"; then
  capture
  if [ "$RC" -eq 0 ]; then
    pass "reconcile toward deployed apply -> equal + plain exit 0"
  else
    fail "reconcile toward deployed apply -> plain exit 0 (rc=$RC, out=$OUT)"
  fi
else
  fail "reconcile toward deployed apply -> equal + plain exit 0 (rc=$RC, out=$OUT)"
fi

# Re-diverge after scenario J so this direction exercises an actual copy.
printf '%s\n' '#!/usr/bin/env bash' 'echo v3-deployed' > "$HERMES_SCRIPTS/fixture_diff.sh"

# --- scenario K: reconcile repo apply ---------------------------------------
capture --reconcile --toward=repo --apply
if [ "$RC" -eq 0 ] && cmp -s "$REPO/fixture_diff.sh" "$HERMES_SCRIPTS/fixture_diff.sh" \
    && grep -q 'v3-deployed' "$REPO/fixture_diff.sh"; then
  capture
  if [ "$RC" -eq 0 ]; then
    pass "reconcile toward repo apply -> equal + plain exit 0"
  else
    fail "reconcile toward repo apply -> plain exit 0 (rc=$RC, out=$OUT)"
  fi
else
  fail "reconcile toward repo apply -> equal + plain exit 0 (rc=$RC, out=$OUT)"
fi

# --- scenario L: no drift with apply -> informational exit 0 ----------------
write_jobs '[{"script": "fixture_ok.sh"}]'
capture --reconcile --toward=deployed --apply
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "INFO: no content drift; nothing to reconcile"; then
  pass "no drift reconcile apply -> INFO: + exit 0"
else
  fail "no drift reconcile apply -> INFO: + exit 0 (rc=$RC, out=$OUT)"
fi

# --- scenario F: unreadable jobs.json -> exit 2 -----------------------------
rm "$CRON_DIR/jobs.json"
capture
if [ "$RC" -eq 2 ]; then
  pass "missing jobs.json -> exit 2"
else
  fail "missing jobs.json -> exit 2 (rc=$RC, out=$OUT)"
fi

# --- additional usage and parse/error-precedence coverage --------------------
write_jobs '[{"script": "fixture_ok.sh"}]'
capture --unknown
if [ "$RC" -eq 64 ]; then
  pass "unknown argument -> exit 64"
else
  fail "unknown argument -> exit 64 (rc=$RC, out=$OUT)"
fi

capture --apply
if [ "$RC" -eq 64 ]; then
  pass "--apply without --reconcile -> exit 64"
else
  fail "--apply without --reconcile -> exit 64 (rc=$RC, out=$OUT)"
fi

capture --toward=repo
if [ "$RC" -eq 64 ]; then
  pass "--toward without --reconcile -> exit 64"
else
  fail "--toward without --reconcile -> exit 64 (rc=$RC, out=$OUT)"
fi

write_jobs '{malformed json'
capture
if [ "$RC" -eq 2 ]; then
  pass "malformed jobs.json -> exit 2"
else
  fail "malformed jobs.json -> exit 2 (rc=$RC, out=$OUT)"
fi

write_jobs '[{"script": "fixture_diff.sh"}, {"script": "missing-hard-error.sh"}]'
printf '%s\n' '#!/usr/bin/env bash' 'echo drift-repo' > "$REPO/fixture_diff.sh"
printf '%s\n' '#!/usr/bin/env bash' 'echo drift-deployed' > "$HERMES_SCRIPTS/fixture_diff.sh"
capture
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q 'ERROR: missing-hard-error.sh'; then
  pass "ERROR masks drift -> exit 1"
else
  fail "ERROR masks drift -> exit 1 (rc=$RC, out=$OUT)"
fi

write_jobs '[{"script": "../unsafe.sh"}]'
capture --reconcile --toward=repo --apply
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "ERROR: unsafe script name"; then
  pass "unsafe script name -> ERROR + exit 1"
else
  fail "unsafe script name -> ERROR + exit 1 (rc=$RC, out=$OUT)"
fi

# --- scenario A: --quiet with no-drift reconcile -> no INFO: line ------------
write_jobs '[{"script": "fixture_ok.sh"}]'
capture --quiet --reconcile --toward=deployed
if [ "$RC" -eq 0 ] && ! printf '%s' "$OUT" | grep -q "INFO:"; then
  pass "--quiet no-drift reconcile -> exit 0 without INFO:"
else
  fail "--quiet no-drift reconcile -> exit 0 without INFO: (rc=$RC, out=$OUT)"
fi

# --- git-based scenarios: dirty-worktree refusal and --force -----------------
# These scenarios re-init a git repo over the fixture root after scenarios A-L
# have already run, so they cannot affect any earlier result.
REPO_ROOT="$TMP/repo"
git_commit() {
  git -C "$REPO_ROOT" -c user.email=test@example.invalid -c user.name=test \
    -c commit.gpgsign=false commit -q -m "$1"
}
git -C "$REPO_ROOT" -c init.defaultBranch=main init -q
git -C "$REPO_ROOT" add -A
git_commit baseline

# --- scenario B: dirty repo worktree refuses --toward=repo --apply -----------
printf '%s\n' '#!/usr/bin/env bash' 'echo v4-deployed' > "$HERMES_SCRIPTS/fixture_diff.sh"
write_jobs '[{"script": "fixture_diff.sh"}]'
printf '%s\n' '#!/usr/bin/env bash' 'echo uncommitted-repo-edit' > "$REPO/$FIX_OK"
repo_diff_before="$(<"$REPO/fixture_diff.sh")"
capture --reconcile --toward=repo --apply
if [ "$RC" -eq 1 ] && printf '%s' "$OUT" | grep -q "repo worktree is dirty" \
    && [ "$(<"$REPO/fixture_diff.sh")" = "$repo_diff_before" ]; then
  pass "dirty repo worktree -> refuse apply + exit 1 + file unchanged"
else
  fail "dirty repo worktree -> refuse apply + exit 1 + file unchanged (rc=$RC, out=$OUT)"
fi

# --- scenario C: --force overrides the refusal and applies the copy ----------
capture --reconcile --toward=repo --apply --force
if [ "$RC" -eq 0 ] && printf '%s' "$OUT" | grep -q "continuing because --force was given" \
    && cmp -s "$REPO/fixture_diff.sh" "$HERMES_SCRIPTS/fixture_diff.sh"; then
  pass "--force on dirty worktree -> exit 0 + repo file equals deployed"
else
  fail "--force on dirty worktree -> exit 0 + repo file equals deployed (rc=$RC, out=$OUT)"
fi

# --- scenario D: --force is only valid with --reconcile --apply --toward=repo -
capture --force
if [ "$RC" -eq 64 ]; then
  pass "--force alone -> exit 64"
else
  fail "--force alone -> exit 64 (rc=$RC, out=$OUT)"
fi

capture --reconcile --toward=deployed --apply --force
if [ "$RC" -eq 64 ]; then
  pass "--force with --toward=deployed -> exit 64"
else
  fail "--force with --toward=deployed -> exit 64 (rc=$RC, out=$OUT)"
fi

# --- scenario E: clean repo worktree applies without --force ------------------
git -C "$REPO_ROOT" add -A
git_commit clean
printf '%s\n' '#!/usr/bin/env bash' 'echo v5-deployed' > "$HERMES_SCRIPTS/fixture_diff.sh"
capture --reconcile --toward=repo --apply
if [ "$RC" -eq 0 ] && cmp -s "$REPO/fixture_diff.sh" "$HERMES_SCRIPTS/fixture_diff.sh" \
    && grep -q 'v5-deployed' "$REPO/fixture_diff.sh"; then
  pass "clean repo worktree -> apply succeeds + exit 0"
else
  fail "clean repo worktree -> apply succeeds + exit 0 (rc=$RC, out=$OUT)"
fi

echo
echo "$PASSED passed, $FAILURES failed"
[ "$FAILURES" -eq 0 ]
