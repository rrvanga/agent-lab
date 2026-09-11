#!/usr/bin/env python3
"""Thermal watchdog for the ThinkPad host.

Silent by default (cron no_agent mode: empty stdout = no message).
Prints an alert only when a temperature crosses its warn/crit threshold.
Exits non-zero only if NO temperature source can be read at all,
so a broken sensor setup surfaces as an error alert instead of silence.

Thresholds (laptop-appropriate):
  CPU  warn 92 / crit 95   (TJmax 100, i7-9750H; single-core turbo bursts
                            briefly hit 85-94 while everything else stays
                            cool -- a single-sample 85 alert is noise)
  GPU  warn 85 / crit 95   (GTX 1650 Max-Q)
  NVMe warn 65 / crit 75

Sustained-warn detection: a warn-level alert requires the SAME sensor to be
over warn on 2 CONSECUTIVE samples (~10 min at 5-min cadence). Transient
turbo blips that recover within one tick stay silent. Crit still alerts
immediately on a single sample -- never silent to real overheating.

State: ~/.hermes/.cache/thermal_watch_state.json (per-sensor consecutive
sample counts); missing/corrupt state simply restarts counting (no false
alerts). Env override for testing: THERMAL_TEST=1 forces all sensors past
crit (immediate alert, proves delivery path).
"""
import glob
import json
import os
import subprocess
import sys

TEST = os.environ.get("THERMAL_TEST") == "1"
STATE_FILE = os.path.expanduser("~/.hermes/.cache/thermal_watch_state.json")
WARN_SAMPLES = 2  # consecutive 5-min samples over warn before warn-alert

# (label, temp_c, warn_c, crit_c)
sensors = []


def read_sysfs_int(path):
    try:
        with open(path) as f:
            return int(f.read().strip())
    except Exception:
        return None


# --- CPU package: prefer kernel thermal zone -------------------------------
try:
    zones = {}
    for z in glob.glob("/sys/class/thermal/thermal_zone*"):
        try:
            with open(f"{z}/type") as f:
                ztype = f.read().strip()
            zones[ztype] = z
        except Exception:
            pass
    cpu_zone = zones.get("x86_pkg_temp") or zones.get("k10temp")
    if cpu_zone:
        t = read_sysfs_int(f"{cpu_zone}/temp")
        if t is not None:
            sensors.append(("CPU pkg", t / 1000.0, 92.0, 95.0))
except Exception:
    pass

# --- GPU: nvidia-smi -------------------------------------------------------
try:
    out = subprocess.run(
        ["nvidia-smi", "--query-gpu=temperature.gpu", "--format=csv,noheader,nounits"],
        capture_output=True, text=True, timeout=10,
    )
    if out.returncode == 0 and out.stdout.strip().isdigit():
        sensors.append(("GPU", float(out.stdout.strip()), 85.0, 95.0))
except Exception:
    pass

# --- NVMe: drive hwmon -----------------------------------------------------
nvme_temps = []
for h in glob.glob("/sys/class/nvme/nvme*/hwmon*"):
    t = read_sysfs_int(f"{h}/temp1_input")
    if t is not None:
        nvme_temps.append(t / 1000.0)
if nvme_temps:
    sensors.append(("NVMe", max(nvme_temps), 65.0, 75.0))

# --- Wi-Fi (informational) -------------------------------------------------
for ztype, zpath in zones.items():
    if "iwlwifi" in ztype:
        t = read_sysfs_int(f"{zpath}/temp")
        if t is not None:
            sensors.append(("Wi-Fi", t / 1000.0, 90.0, 95.0))
        break

# --- Fans (diagnostic only: shown in alerts, never affects silence) ---------
fans = []
for h in glob.glob("/sys/class/hwmon/hwmon*"):
    for fan in sorted(glob.glob(f"{h}/fan*_input")):
        r = read_sysfs_int(fan)
        if r is not None:
            fans.append((os.path.basename(fan).replace("_input", ""), r))
    if fans:
        break

# --- Report ----------------------------------------------------------------
if not sensors:
    print("❌ thermal_watch: no temperature sources readable (CPU/GPU/NVMe all failed)")
    sys.exit(1)

if TEST:
    # force every sensor past its crit threshold while keeping the real
    # thresholds in the alert text (so test output matches prod wording);
    # crit path is immediate, no state persisted
    sensors = [(lbl, max(t, c + 15.0), w, c) for lbl, t, w, c in sensors]


def load_state():
    try:
        with open(STATE_FILE) as f:
            return json.load(f)
    except Exception:
        return {}


def save_state(state):
    try:
        os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
        tmp = STATE_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(state, f)
        os.replace(tmp, STATE_FILE)
    except Exception:
        pass


state = {} if TEST else load_state()
alerts = []
worst = 0.0
new_state = {}
for label, t, warn, crit in sensors:
    worst = max(worst, t)
    if t >= crit:
        # crit always alerts on the first sample it's seen
        alerts.append(f"🔴 {label}: {t:.1f}°C  (CRITICAL, crit {crit:.0f})")
        new_state[label] = 0
    elif t >= warn:
        # warn alerts only on the 2nd consecutive sample over warn
        count = state.get(label, 0) + 1
        new_state[label] = count
        if count >= WARN_SAMPLES:
            alerts.append(f"⚠️ {label}: {t:.1f}°C  (warn {warn:.0f}, "
                          f"{count} consecutive samples)")
    else:
        new_state[label] = 0
if not TEST:
    save_state(new_state)

if alerts:
    summary = "\n".join(f"  {l}: {t:.1f}°C" for l, t, _, _ in sensors)
    fan_line = ""
    if fans:
        fan_line = "\nFans: " + " | ".join(f"{l} {r} RPM" for l, r in fans)
    print(f"🌡️ THERMAL ALERT — ThinkPad\n" + "\n".join(alerts) + f"\nAll temps:\n{summary}{fan_line}")
