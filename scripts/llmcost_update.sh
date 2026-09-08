#!/usr/bin/env bash
# Cron entry: run llmcost's in-repo daily update (fetch → normalize → diff → commit if changed).
# Keeps the real logic version-controlled in the repo; this is just a thin pointer.
bash "$HOME/dev/llmcost/scripts/update.sh"
