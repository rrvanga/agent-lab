#!/usr/bin/env python3
"""cron_sentinel.py — scheduler health + dormancy sentinel (user pref: 2026-09-05).

SILENT ON NORMAL: empty stdout, exit 0 when everything is healthy.
LOUD ON ANOMALY: prints findings + exit 1 (cron delivers the message).

Checks:
  1. Built-in `hermes cron doctor` — failed runs, delivery errors, overdue
     next_run_at ("job is not firing"), config problems. Exit 0 = healthy.
  2. Removed-job diff — jobs.json job ids compared against a baseline file.
     A job that silently disappears from the schedule (the classic dormancy
     failure) raises ONE alert, then the baseline adopts the current set so
     intentional removals don't alert forever.

State: ~/.hermes/cron/.cron-sentinel-baseline.json (auto-seeds on first run)
"""
import json
import os
import subprocess
import sys

HERMES = os.path.expanduser("~/.hermes/hermes-agent/venv/bin/hermes")
JOBS_JSON = os.path.expanduser("~/.hermes/cron/jobs.json")
BASELINE = os.path.expanduser("~/.hermes/cron/.cron-sentinel-baseline.json")


def main() -> int:
    problems: list[str] = []

    # --- 1. built-in scheduler health check -------------------------------
    # NOTE: `hermes cron doctor` ALWAYS exits 0 (CLI swallows the subcommand
    # rc) — findings appear only in stdout. Gate on OUTPUT, not return code.
    try:
        proc = subprocess.run(
            [HERMES, "cron", "doctor"],
            capture_output=True, text=True, timeout=120,
        )
        body = (proc.stdout or "").strip()
        if not body:
            if proc.returncode != 0:
                problems.append(
                    f"hermes cron doctor produced no output (rc={proc.returncode})")
        elif "no issues" not in body:
            problems.append(body)
    except Exception as exc:  # noqa: BLE001
        problems.append(f"hermes cron doctor could not run: {exc}")

    # --- 2. removed-job diff against baseline -----------------------------
    try:
        with open(JOBS_JSON, encoding="utf-8") as fh:
            data = json.load(fh)
        jobs = data["jobs"] if isinstance(data, dict) else data
        current = {
            j.get("id"): j.get("name", "?")
            for j in jobs if isinstance(j, dict) and j.get("id")
        }
        baseline: dict = {}
        if os.path.exists(BASELINE):
            with open(BASELINE, encoding="utf-8") as fh:
                baseline = json.load(fh)
        if baseline:
            for jid, name in baseline.items():
                if jid not in current:
                    problems.append(
                        f"expected job no longer scheduled: {name} ({jid}) "
                        "— deliberate removal? baseline auto-updated."
                    )
        # adopt current set (seeds first run; accepts new jobs silently)
        with open(BASELINE, "w", encoding="utf-8") as fh:
            json.dump(current, fh, indent=2, sort_keys=True)
    except Exception as exc:  # noqa: BLE001
        problems.append(f"cron jobs.json read failed: {exc}")

    if problems:
        sys.stdout.write(f"cron-sentinel: {len(problems)} problem(s)\n\n")
        sys.stdout.write("\n\n".join(problems) + "\n")
        return 1
    return 0  # silent success — cron delivers nothing


if __name__ == "__main__":
    sys.exit(main())
