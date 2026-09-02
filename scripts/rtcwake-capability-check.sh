#!/usr/bin/env bash
# Read-only RTC wake capability probe for issue #5 (overnight power
# management). Zero writes: never invokes rtcwake and never touches the
# wakealarm sysfs file; it only reads system facts and reports PASS/FAIL per
# check, then a final RTC_WAKE_CAPABLE line.
set -u

SYSFS_RTC=/sys/class/rtc/rtc0
PROC_RTC=/proc/driver/rtc
failed=0

pass() { printf 'PASS: %s\n' "$1"; }
fail() { printf 'FAIL: %s\n' "$1"; failed=1; }

# 1. rtcwake binary must exist (util-linux).
if rtcwake_path=$(command -v rtcwake 2>/dev/null); then
    pass "rtcwake binary found at $rtcwake_path"
else
    fail "rtcwake binary not found in PATH (util-linux required)"
fi

# 2. wakealarm sysfs attribute must exist and be readable (readable by all
#    on this host, mode 0644; only root can write it, which is fine here).
if [ -r "$SYSFS_RTC/wakealarm" ]; then
    pass "$SYSFS_RTC/wakealarm exists and is readable"
else
    fail "$SYSFS_RTC/wakealarm missing or not readable"
fi

# 3. /proc/driver/rtc must be readable and report the fields we rely on.
if [ -r "$PROC_RTC" ] && grep -q 'rtc_time' "$PROC_RTC" && grep -q 'batt_status' "$PROC_RTC"; then
    pass "/proc/driver/rtc readable; reports rtc_time and batt_status"
else
    fail "/proc/driver/rtc missing, unreadable, or lacks rtc_time/batt_status"
fi

# 4. RTC driver must be rtc_cmos (the ACPI PNP0B00 driver on this host).
driver=$(grep -m 1 '^DRIVER=' "$SYSFS_RTC/device/uevent" 2>/dev/null | cut -d= -f2-)
if [ -n "$driver" ] && [ "$driver" = "rtc_cmos" ]; then
    pass "RTC driver is rtc_cmos (DRIVER=$driver)"
else
    fail "RTC driver is not rtc_cmos (DRIVER=${driver:-<none found>})"
fi

# Record the current alarm/battery state for the record.
if [ -r "$PROC_RTC" ]; then
    grep -E '^(alrm_time|alrm_date|alarm_IRQ|batt_status)' "$PROC_RTC" |
        sed 's/^/RTC record: /'
fi

if [ "$failed" -eq 0 ]; then
    printf 'RTC_WAKE_CAPABLE: yes\n'
    exit 0
fi
printf 'RTC_WAKE_CAPABLE: no\n'
exit 1