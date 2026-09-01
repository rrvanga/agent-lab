#!/usr/bin/env bash
# Mocked test harness for nightly-shutdown.sh. No root required and no writes
# to the real RTC: rtcwake/systemctl/poweroff/logger are shadowed by mock
# executables in a temp bin dir and RTC_SYSFS points at a temp dir, so nothing
# on the host is touched. T1 additionally runs the real capability probe
# against the real sysfs/proc (read-only).
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
NIGHTLY="$ROOT/scripts/nightly-shutdown.sh"
CAPABILITY="$ROOT/scripts/rtcwake-capability-check.sh"

TEST_TMP=$(mktemp -d)
MOCK_BIN="$TEST_TMP/mockbin"
RTC_DIR="$TEST_TMP/rtc"
MOCK_LOG="$TEST_TMP/mock_log"
mkdir -p "$MOCK_BIN" "$RTC_DIR"
trap 'rm -rf "$TEST_TMP"' EXIT

# --- mock executables -------------------------------------------------------
cat > "$MOCK_BIN/rtcwake" <<'EOF'
#!/usr/bin/env bash
printf '%s %s MOCK_RTCWAKE_FAIL=%s\n' "$0" "$*" "${MOCK_RTCWAKE_FAIL:-0}" >> "$MOCK_LOG"
if [ "${MOCK_RTCWAKE_FAIL:-0}" = "1" ]; then
    exit 1
fi
printf '1680482700' > "$RTC_SYSFS/wakealarm"
exit 0
EOF
chmod +x "$MOCK_BIN/rtcwake"

cat > "$MOCK_BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf '%s %s MOCK_SYSTEMCTL_FAIL=%s\n' "$0" "$*" "${MOCK_SYSTEMCTL_FAIL:-0}" >> "$MOCK_LOG"
if [ "${MOCK_SYSTEMCTL_FAIL:-0}" = "1" ]; then
    exit 1
fi
exit 0
EOF
chmod +x "$MOCK_BIN/systemctl"

cat > "$MOCK_BIN/poweroff" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$0" "$*" >> "$MOCK_LOG"
exit 0
EOF
chmod +x "$MOCK_BIN/poweroff"

cat > "$MOCK_BIN/logger" <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$0" "$*" >> "$MOCK_LOG"
exit 0
EOF
chmod +x "$MOCK_BIN/logger"

fails=0

# Reset per-test state: empty mock log + wakealarm file, clear test-only vars.
reset_state() {
    : > "$MOCK_LOG"
    : > "$RTC_DIR/wakealarm"
    unset FAKE_NOW WAKE_TIME MOCK_RTCWAKE_FAIL MOCK_SYSTEMCTL_FAIL 2>/dev/null || true
}

# Run the nightly script with the mock PATH. Env vars are exported by the
# caller before invoking.
run_nightly() {
    PATH="$MOCK_BIN:$PATH" bash "$NIGHTLY" "$@" >/dev/null 2>&1
}

# T1 capability probe: real script, mocked PATH so command -v rtcwake passes.
reset_state
out=$(PATH="$MOCK_BIN:$PATH" bash "$CAPABILITY" 2>&1)
rc=$?
if [ "$rc" -eq 0 ] && printf '%s\n' "$out" | grep -q 'RTC_WAKE_CAPABLE: yes'; then
    echo "PASS: T1 capability"
else
    echo "FAIL: T1 capability (rc=$rc)"
    fails=$((fails + 1))
fi

# T2 shutdown-ok: 23:00, in window, wake 06:45 tomorrow (< 12h) -> powers off.
reset_state
export FAKE_NOW="2026-08-31 23:00"
export WAKE_TIME=06:45
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --shutdown
rc=$?
rtc_line=$(awk '/rtcwake -m no/{print NR; exit}' "$MOCK_LOG")
pow_line=$(awk '/systemctl poweroff/{print NR; exit}' "$MOCK_LOG")
if [ "$rc" -eq 0 ] && [ -n "$rtc_line" ] && [ -n "$pow_line" ] && [ "$rtc_line" -lt "$pow_line" ]; then
    echo "PASS: T2 shutdown-ok"
else
    echo "FAIL: T2 shutdown-ok (rc=$rc)"
    fails=$((fails + 1))
fi

# T3 shutdown-out-of-window: 17:00 is outside 22:00..02:00 -> must stay on.
reset_state
export FAKE_NOW="2026-08-31 17:00"
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --shutdown
rc=$?
if [ "$rc" -ne 0 ] && ! grep -q 'systemctl poweroff' "$MOCK_LOG"; then
    echo "PASS: T3 shutdown-out-of-window"
else
    echo "FAIL: T3 shutdown-out-of-window (rc=$rc)"
    fails=$((fails + 1))
fi

# T4 shutdown-rtcwake-fail: alarm arming fails -> must not power off.
reset_state
export FAKE_NOW="2026-08-31 23:00"
export MOCK_RTCWAKE_FAIL=1
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --shutdown
rc=$?
if [ "$rc" -ne 0 ] && ! grep -q 'systemctl poweroff' "$MOCK_LOG"; then
    echo "PASS: T4 shutdown-rtcwake-fail"
else
    echo "FAIL: T4 shutdown-rtcwake-fail (rc=$rc)"
    fails=$((fails + 1))
fi

# T5 alarm-only: arms with rtcwake -m no, verifies, then clears the alarm.
reset_state
export FAKE_NOW="2026-08-31 10:00"
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --alarm-only
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'rtcwake -m no' "$MOCK_LOG" && [ ! -s "$RTC_DIR/wakealarm" ]; then
    echo "PASS: T5 alarm-only"
else
    echo "FAIL: T5 alarm-only (rc=$rc)"
    fails=$((fails + 1))
fi

# T6 wake-too-far: wake 12:00 from 23:00 resolves > 12h ahead -> must stay on.
reset_state
export FAKE_NOW="2026-08-31 23:00"
export WAKE_TIME=12:00
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --shutdown
rc=$?
if [ "$rc" -ne 0 ] && ! grep -q 'systemctl poweroff' "$MOCK_LOG"; then
    echo "PASS: T6 wake-too-far"
else
    echo "FAIL: T6 wake-too-far (rc=$rc)"
    fails=$((fails + 1))
fi

# T7 reversed-window-refused: 02:00..22:00 is a 20h window (> MAX_WINDOW_HOURS)
# -> config refusal (exit 2); no poweroff and no rtcwake line in the mock log.
reset_state
export FAKE_NOW="2026-08-31 15:00"
export NIGHT_START=02:00
export NIGHT_END=22:00
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --shutdown
rc=$?
if [ "$rc" -eq 2 ] && ! grep -q 'poweroff' "$MOCK_LOG" && ! grep -q 'rtcwake' "$MOCK_LOG"; then
    echo "PASS: T7 reversed-window-refused"
else
    echo "FAIL: T7 reversed-window-refused (rc=$rc)"
    fails=$((fails + 1))
fi
unset NIGHT_START NIGHT_END 2>/dev/null || true

# T8 early-morning-no-rollover: 00:30 is inside 22:00..02:00, wake 06:45
# resolves to the SAME day (the +86400 branch must NOT trigger) -> powers off.
reset_state
export FAKE_NOW="2026-08-31 00:30"
export RTC_SYSFS="$RTC_DIR"
export MOCK_LOG="$MOCK_LOG"
run_nightly --shutdown
rc=$?
if [ "$rc" -eq 0 ] && grep -q 'systemctl poweroff' "$MOCK_LOG"; then
    echo "PASS: T8 early-morning-no-rollover"
else
    echo "FAIL: T8 early-morning-no-rollover (rc=$rc)"
    fails=$((fails + 1))
fi

if [ "$fails" -eq 0 ]; then
    echo "ALL TESTS PASSED"
    exit 0
fi
exit 1