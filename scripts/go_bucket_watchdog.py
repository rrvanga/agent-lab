#!/usr/bin/env python3
"""Go bucket watchdog — runs the fixed token usage report and alerts ONLY when a
bucket is climbing toward the cap. Silent output = no delivery (watchdog pattern).
Covers the mid-day gap: the 07:30 report can't see a burst that starts at 14:00.
"""
import subprocess, sys, re, os

REPORT = os.path.expanduser("~/.hermes/scripts/token_usage_report.py")
# Thresholds (override via env for testing; cron runs use the defaults)
T5 = float(os.environ.get('GO_WATCH_5H', '50'))
T7 = float(os.environ.get('GO_WATCH_7D', '60'))

out = subprocess.run([sys.executable, REPORT],
                     capture_output=True, text=True, timeout=90)
if out.returncode != 0:
    print(f'⚠ Go watchdog: report script failed ({out.returncode}): {out.stderr[:200]}')
    sys.exit(0)

m = re.search(r'Go quota:\s*(.+?)\s*used', out.stdout)
if not m:
    sys.exit(0)  # no quota line -> nothing to report

quota = m.group(1)
pcts = {}
for part in quota.split('·'):
    part = part.strip()
    mm = re.match(r'([0-9hwd]+):\s*([0-9.<]+)%', part)
    if mm:
        pcts[mm.group(1)] = float(mm.group(2).replace('<', '0'))

h5 = pcts.get('5h', 0.0)
d7 = pcts.get('7d', 0.0)

warnings = []
if h5 >= T5:
    warnings.append(f'5h bucket at {h5:.0f}% — heavy burst: switch to a lighter model or pause')
if d7 >= T7:
    warnings.append(f'7d bucket at {d7:.0f}% — weekly cap approaching ({quota})')

if warnings:
    print('⚠️ Go usage watch: ' + '; '.join(warnings) + ' — cap-hit fallback ready: nemotron-3-ultra-free (free tier, zen/v1)')
