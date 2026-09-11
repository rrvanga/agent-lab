#!/usr/bin/env bash
# Thin cron wrapper -> real logic lives in the agent-lab repo.
exec bash "$HOME/dev/agent-lab/scripts/render_and_commit.sh"
