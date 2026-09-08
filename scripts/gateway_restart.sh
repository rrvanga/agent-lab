#!/bin/bash
# Delayed gateway restart helper — fired by systemd-run (transient timer),
# detached from the gateway process tree so it survives the restart it triggers.
sleep 1
systemctl --user restart hermes-gateway
echo "gateway restart command issued at $(date '+%H:%M:%S')" >> "$HOME/.hermes/gateway-restart.log"