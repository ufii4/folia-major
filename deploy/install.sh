#!/bin/bash
# Install folia-server as a per-user launchd service.
set -euo pipefail

PLIST_SRC="$(cd "$(dirname "$0")" && pwd)/com.ufii.folia-server.plist"
PLIST_DST="$HOME/Library/LaunchAgents/com.ufii.folia-server.plist"
LABEL="com.ufii.folia-server"
UID_NUM="$(id -u)"

mkdir -p "$HOME/Library/LaunchAgents"
cp "$PLIST_SRC" "$PLIST_DST"

launchctl bootout "gui/$UID_NUM/$LABEL" 2>/dev/null || true
launchctl bootstrap "gui/$UID_NUM" "$PLIST_DST"

echo "installed. status:"
launchctl print "gui/$UID_NUM/$LABEL" | grep -E "state|pid" | head -3
echo
echo "client token (share to your devices, keep off the internet):"
cat "$HOME/Library/Application Support/folia-server/token"
echo
