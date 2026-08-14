#!/usr/bin/env bash
# Refresh the architecture diagram from live state; commit & push only on change.
# Designed for a no-agent cron: silent (exit 0, no stdout) when nothing changed.
set -euo pipefail
cd "$(dirname "$0")/.."   # agent-lab repo root

python3 scripts/render_architecture.py >/dev/null

if git diff --quiet -- assets/architecture.png assets/architecture.html; then
    exit 0   # unchanged: stay silent, leave the tree as-is
fi

git add assets/architecture.png assets/architecture.html
git commit -q -m "docs: refresh architecture diagram (auto)"
git push -q origin main
echo "architecture diagram updated -> $(git rev-parse --short HEAD)"
