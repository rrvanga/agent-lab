#!/usr/bin/env bash
# Guarded overnight shutdown + RTC wake for issue #5.
#
# Fail-closed by design: every guard must pass in order or the script aborts
# with a printed reason and the machine stays on. A stray or mistimed run can
# therefore never power the machine off outside the approved night window.
#
# The real power paths (--shutdown and the wakealarm writes in --alarm-only)
# require root. FAKE_NOW is a test hook: set it to "YYYY-MM-DD HH:MM" and
# every "now" computation uses that instant instead of `date`.
set -u

WAKE_TIME=${WAKE_TIME:-06:45}
NIGHT_START=${NIGHT_START:-22:00}
NIGHT_END=${NIGHT_END:-02:00}
MAX_WINDOW_HOURS=12  # maximum overnight window length in hours; guards against reversed start/end config
RTC_SYSFS=${RTC_SYSFS:-/sys/class/rtc/rtc0}
FAKE_NOW=${FAKE_NOW:-}

usage() {
    cat <<'EOF'
usage: nightly-shutdown.sh MODE

Modes:
  --shutdown    Full armed run: every guard must pass (root, night window,
                wake time sane and < 12h ahead, alarm armed and accepted),
                then the machine powers off.
  --alarm-only  Safe probe: arm the alarm for WAKE_TIME with rtcwake -m no,
                read it back, then clear it. Never powers off.

Environment (all optional, overridable for tests):
  WAKE_TIME    HH:MM local time the machine must be back on (default 06:45)
  NIGHT_START  HH:MM start of the allowed night window (default 22:00)
  NIGHT_END    HH:MM end of the allowed night window; spans midnight (default 02:00)
  RTC_SYSFS    sysfs RTC dir (default /sys/class/rtc/rtc0)
  FAKE_NOW     test hook "YYYY-MM-DD HH:MM"; fake the current time
EOF
}

log() {
    echo "nightly-shutdown: $*" >&2
    logger -t nightly-shutdown "$*"
}

# Current local time as an integer HHMM.
now_hhmm() {
    if [ -n "$FAKE_NOW" ]; then
        date -d "$FAKE_NOW" +%H%M
    else
        date +%H%M
    fi
}

# Return 0 if now is inside NIGHT_START..NIGHT_END. The window spans
# midnight, so in integer-HHMM terms it is valid before midnight from START
# to 23:59 (now >= START) and after midnight from 00:00 to END (now < END).
in_night_window() {
    local now start end
    now=$((10#$(now_hhmm)))
    start=$((10#${NIGHT_START//:/}))
    end=$((10#${NIGHT_END//:/}))
    [ "$now" -ge "$start" ] || [ "$now" -lt "$end" ]
}

validate_window_config() {
    local start end len
    start=$((10#${NIGHT_START//:/}))
    end=$((10#${NIGHT_END//:/}))
    if [ "$start" -le "$end" ]; then
        len=$(( (end - start) / 100 ))
    else
        len=$(( (2400 - start + end) / 100 ))
    fi
    if [ "$start" -eq "$end" ] || [ "$len" -gt "$MAX_WINDOW_HOURS" ] || [ "$len" -le 0 ]; then
        echo "nightly-shutdown: invalid night window NIGHT_START=$NIGHT_START NIGHT_END=$NIGHT_END (length ${len}h > max ${MAX_WINDOW_HOURS}h or degenerate); refusing to run" >&2
        exit 2
    fi
    # The window must span midnight (evening start, early-morning end): the
    # in-window predicate is an OR union that is only correct for start>end.
    if [ "$start" -le "$end" ]; then
        echo "nightly-shutdown: invalid night window NIGHT_START=$NIGHT_START NIGHT_END=$NIGHT_END (window must span midnight: NIGHT_START must be > NIGHT_END); refusing to run" >&2
        exit 2
    fi
}

# Return 0 if WAKE_TIME is a valid HH:MM in 00:00..23:59.
validate_wake_time() {
    local hh mm
    case "$WAKE_TIME" in
        [0-2][0-9]:[0-5][0-9])
            hh=$((10#${WAKE_TIME%%:*}))
            mm=$((10#${WAKE_TIME##*:}))
            [ "$hh" -le 23 ] && [ "$mm" -le 59 ]
            ;;
        *)
            return 1
            ;;
    esac
}

# Print the epoch for WAKE_TIME: today's if it is still ahead, otherwise
# tomorrow's. With a max_hours argument, refuse (return 1) when the resolved
# time is more than max_hours ahead of now.
wake_epoch() {
    local max_hours="${1:-}" now_ts today candidate diff
    if [ -n "$FAKE_NOW" ]; then
        now_ts=$(date -d "$FAKE_NOW" +%s)
        today=$(date -d "$FAKE_NOW" +%Y-%m-%d)
    else
        now_ts=$(date +%s)
        today=$(date +%Y-%m-%d)
    fi
    candidate=$(date -d "$today $WAKE_TIME" +%s)
    if [ "$candidate" -le "$now_ts" ]; then
        candidate=$((candidate + 86400))
    fi
    diff=$((candidate - now_ts))
    if [ -n "$max_hours" ] && [ "$diff" -gt $((max_hours * 3600)) ]; then
        log "wake time $WAKE_TIME resolves to $((diff / 3600))h ahead (limit ${max_hours}h)"
        return 1
    fi
    printf '%s\n' "$candidate"
}

# Arm the RTC alarm via rtcwake for the given mode (no|off).
set_alarm() {
    local mode="$1" epoch="$2"
    if ! rtcwake -m "$mode" -t "$epoch"; then
        log "rtcwake -m $mode -t $epoch failed"
        return 1
    fi
    return 0
}

# Read the wakealarm back and confirm it is non-empty (kernel accepted it).
verify_alarm() {
    local alarm
    alarm=$(cat "$RTC_SYSFS/wakealarm" 2>/dev/null || true)
    if [ -n "$alarm" ]; then
        log "wakealarm armed: $alarm"
        return 0
    fi
    log "wakealarm empty or unreadable; alarm not accepted"
    return 1
}

# Clear the alarm and confirm it reads back empty. The kernel sysfs handler
# clears on any write, so we write "0"; the empty truncate that follows keeps
# the file empty in the file-based tests and is a no-op for the real sysfs.
clear_alarm() {
    if [ -w "$RTC_SYSFS/wakealarm" ]; then
        printf '0' > "$RTC_SYSFS/wakealarm" 2>/dev/null || return 1
        : > "$RTC_SYSFS/wakealarm" 2>/dev/null || return 1
    else
        log "$RTC_SYSFS/wakealarm not writable; cannot clear"
        return 1
    fi
    if [ -n "$(cat "$RTC_SYSFS/wakealarm" 2>/dev/null || true)" ]; then
        log "wakealarm still non-empty after clear"
        return 1
    fi
    return 0
}

cmd_alarm_only() {
    local epoch
    if [ -z "$FAKE_NOW" ] && [ "$(id -u)" -ne 0 ]; then
        log "alarm-only requires root to write $RTC_SYSFS/wakealarm; run with sudo"
        exit 2
    fi
    if ! validate_wake_time; then
        log "invalid WAKE_TIME '$WAKE_TIME'"
        exit 2
    fi
    epoch=$(wake_epoch) || exit 1
    if ! set_alarm no "$epoch"; then
        log "rtcwake failed; attempting to clear"
        clear_alarm || log "clear failed"
        exit 1
    fi
    if ! verify_alarm; then
        log "verification failed; attempting to clear"
        clear_alarm || log "clear failed"
        exit 1
    fi
    log "alarm verified ($WAKE_TIME, epoch $epoch); clearing"
    if ! clear_alarm; then
        log "failed to clear alarm"
        exit 1
    fi
    log "alarm-only check complete"
    exit 0
}

cmd_shutdown() {
    local epoch
    # Guard (a): must be root to power off, unless FAKE_NOW stands in (test).
    if [ -z "$FAKE_NOW" ] && [ "$(id -u)" -ne 0 ]; then
        log "shutdown requires root (systemctl poweroff); run with sudo"
        exit 2
    fi
    # Guard (b): only run inside the night window.
    if ! in_night_window; then
        log "refusing: local time $(now_hhmm) outside window $NIGHT_START..$NIGHT_END"
        exit 1
    fi
    # Guard (c): WAKE_TIME must parse and resolve to < 12h ahead.
    if ! validate_wake_time; then
        log "invalid WAKE_TIME '$WAKE_TIME'"
        exit 1
    fi
    epoch=$(wake_epoch 12) || exit 1
    # Guard (d): arm the RTC alarm only (rtcwake -m no never powers off; the
    # machine stays on) and confirm the kernel accepted it.
    if ! set_alarm no "$epoch"; then
        log "rtcwake failed; machine stays on"
        exit 1
    fi
    if ! verify_alarm; then
        log "wakealarm not accepted; machine stays on"
        exit 1
    fi
    # Guard (e): record intent, then power off explicitly.
    log "armed: wake $WAKE_TIME (epoch $epoch)"
    if ! systemctl poweroff; then
        log "systemctl poweroff failed; machine stays on"
        exit 1
    fi
    exit 0
}

validate_window_config

case "${1:-}" in
    '')
        echo "error: no mode given" >&2
        usage
        exit 2
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    --alarm-only)
        [ "$#" -gt 1 ] && { echo "error: unexpected argument" >&2; usage; exit 2; }
        cmd_alarm_only
        ;;
    --shutdown)
        [ "$#" -gt 1 ] && { echo "error: unexpected argument" >&2; usage; exit 2; }
        cmd_shutdown
        ;;
    *)
        echo "error: unknown mode '$1'" >&2
        usage
        exit 2
        ;;
esac