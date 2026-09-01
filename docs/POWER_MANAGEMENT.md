# POWER_MANAGEMENT.md — overnight shutdown + RTC wake (issue #5)

Objective (issue #5, overnight power management): the machine powers off at
night for **zero draw** and wakes itself before the 07:00 Morning Brief cron,
so no brief is ever missed. This document covers the SAFE ground-work that
landed in this repo: a read-only capability probe, a fail-closed guarded
shutdown script, and a mocked test harness. Nothing here powers anything off
by itself — nothing is scheduled, and no cron/systemd unit exists yet. A real
overnight run is a staged, operator-only action performed later (see
[LIVE TEST procedure](#staged-live-test-procedure-authorized-operator-sudo)).

## Why the shutdown is fail-closed

The design rule: **a stray run must never kill the machine off-window.** The
blast-radius reasoning that shapes every guard in `nightly-shutdown.sh`:

- The script is delivered as a repo artifact and could be run by hand, by a
  mis-typed command, or by a future timer added at the wrong time. If any one
  guard fails, the machine **stays on** and the alarm is left untouched.
- Guards are checked in order and are all-or-nothing: euid 0 (a non-root run
  cannot power off, and must never fake it), the current local time is inside
  the 22:00–02:00 midnight-spanning window, `WAKE_TIME` parses and resolves to
  a point strictly in the future and within 12 hours, the RTC alarm is actually
  accepted (re-read from `wakealarm`), and only then does `systemctl poweroff`
  run.
- `--alarm-only` is the deliberately safe mode: it arms the alarm, reads it
  back, then **clears** it. It never powers off and is safe to run anytime.

## Scripts

- `scripts/rtcwake-capability-check.sh` — read-only probe. Zero writes: never
  invokes `rtcwake`, never touches `wakealarm`. Exits 0 only if all four
  checks pass (rtcwake present, `wakealarm` present + readable,
  `/proc/driver/rtc` reports `rtc_time`/`batt_status`, driver is `rtc_cmos`).
- `scripts/nightly-shutdown.sh` — the guarded shutdown+wake script, modes
  `--shutdown` and `--alarm-only`.
- `scripts/test-nightly-shutdown.sh` — self-contained mocked harness. No root,
  no writes to the real RTC; `rtcwake`/`systemctl`/`poweroff`/`logger` are
  mocked and `RTC_SYSFS` points at a temp dir.

## Usage

```
bash scripts/rtcwake-capability-check.sh    # read-only; safe as non-root
bash scripts/test-nightly-shutdown.sh       # mocked; safe as non-root
sudo scripts/nightly-shutdown.sh --alarm-only   # arm + verify + clear
sudo scripts/nightly-shutdown.sh --shutdown     # guarded full run
```

The guard config is environment-driven, with defaults that match this host:

```
WAKE_TIME=06:45        # HH:MM local — machine must be back on by then
NIGHT_START=22:00      # allowed shutdown window start
NIGHT_END=02:00        # allowed shutdown window end (spans midnight)
RTC_SYSFS=/sys/class/rtc/rtc0
```

`FAKE_NOW="YYYY-MM-DD HH:MM"` is a test hook that replaces `date` for every
"now" computation (and bypasses the root check); it is used by the harness and
is never meant for production.

## Capability check

On this machine (Arch, util-linux `rtcwake`, RTC `rtc_cmos` — ACPI PNP0B00,
confirmed 2026-08-31) the expected output is:

```
PASS: rtcwake binary found at /usr/bin/rtcwake
PASS: /sys/class/rtc/rtc0/wakealarm exists and is readable
PASS: /proc/driver/rtc readable; reports rtc_time and batt_status
PASS: RTC driver is rtc_cmos (DRIVER=rtc_cmos)
RTC record: alrm_time	: 00:00:00
RTC record: alrm_date	: 2026-09-01
RTC record: alarm_IRQ	: no
RTC record: batt_status	: okay
RTC_WAKE_CAPABLE: yes
```

(Verified live 2026-08-31: output above is the real probe run on this host.
The `RTC record:` lines are informational — current alarm state + battery
status, and vary run to run; the `RTC_WAKE_CAPABLE: yes` line and exit code 0
are the pass/fail answer.)

## Staged LIVE TEST procedure (authorized operator, sudo)

Run in order. Nothing in this repo is scheduled yet, so each stage is manual
and deliberate.

1. **Stage 1 — alarm-only safety probe.** Verify the RTC round-trip without
   touching power state:

   ```
   sudo scripts/nightly-shutdown.sh --alarm-only
   ```

   Expect: the script arms the alarm for `WAKE_TIME`, reads it back, clears
   it, and exits 0.

2. **Stage 2 — empirical 5-minute S5 test (the firmware wake-from-S5 test
   issue #5 calls for).** This is the first real proof that the RTC can wake
   the machine from full power-off:

   ```
   sudo rtcwake -m off -s 300
   ```

   The machine powers off for 300 seconds, then the firmware RTC alarm wakes
   it. Confirm it returns on its own (SSH back in / check the console) — this
   validates `rtc_cmos` wake-from-S5 before any overnight reliance.

3. **Stage 3 — first real overnight run.** After stages 1 and 2 pass, run the
   full armed shutdown one evening:

   ```
   sudo scripts/nightly-shutdown.sh --shutdown
   ```

   It re-checks the window and wake time, arms the alarm with 'rtcwake -m no'
   (arm-only — the machine stays on), re-verifies the alarm from the wakealarm
   sysfs, then powers off explicitly; verification happens BEFORE the poweroff.
   After poweroff the RTC alarm stays armed through S5; the RTC wake alarm is
   one-shot and is cleared when it fires (or is re-armed/cleared on next boot),
   so no stale re-wake occurs. Verify the machine is back before 07:00.

4. **Stage 4 — acceptance.** Over one week, no 07:00 Morning Brief may be
   missed. Only after that should any timer be added to make this automatic.

## Rollback

If the alarm is armed and must be cancelled immediately:

```
sudo sh -c 'echo 0 > /sys/class/rtc/rtc0/wakealarm'
sudo rtcwake -m cancel
```

`rtcwake -m cancel` is the util-linux equivalent; both clear the RTC wake
alarm. A failed `--shutdown` run never gets this far — guards abort before
arming, so the machine simply stays on.

## Disabling a timer added later

No cron/systemd unit ships with this change. If a timer is added later (after
stage 4 acceptance), it can be disabled with its own unit's disable command,
e.g. for a systemd timer:

```
sudo systemctl disable --now nightly-shutdown.timer
```

and the standing alarm can be cleared with the rollback commands above. The
fail-closed guards remain the backstop regardless of what triggers the script.