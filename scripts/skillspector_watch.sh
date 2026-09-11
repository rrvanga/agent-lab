#!/usr/bin/env bash
# skillspector weekly delta watchdog: prints ONLY new findings vs baseline (empty output = silent)
set -u
BASE="$HOME/.hermes/skillspector-baseline.json"
SCAN_JSON=$(mktemp /tmp/sk_watch.XXXXXX.json)

env -u PYTHONPATH "$HOME/.local/bin/skillspector" scan "$HOME/.hermes/skills" \
  --baseline "$BASE" --no-llm -f json -o "$SCAN_JSON" >/dev/null 2>&1

env -u PYTHONPATH python3 - "$SCAN_JSON" <<'EOF'
import json, sys
d = json.load(open(sys.argv[1]))
issues = d['issues'] if isinstance(d, dict) else d
if not issues:
    sys.exit(0)
print(f"skillspector: {len(issues)} NEW finding(s) vs baseline")
seen = set()
for i in issues:
    loc = i.get('location', {})
    key = (i.get('id'), loc.get('file'), loc.get('start_line'))
    if key in seen:
        continue
    seen.add(key)
    print(f"- [{i.get('id')} conf {i.get('confidence', '?')}] {loc.get('file')}:{loc.get('start_line')}")
    print(f"  {str(i.get('finding', ''))[:160]}")
print("Review: env -u PYTHONPATH ~/.local/bin/skillspector scan ~/.hermes/skills")
EOF
rm -f "$SCAN_JSON"
