#!/bin/bash
# Build, sign, install, and launch Folia on a physical iOS device.
#
# Codesigning requires the user's Aqua session; agent processes under the
# craft-agent system LaunchDaemon see 0 identities. The build therefore runs
# through ~/dev/craft-signing-runner (a gui/502 LaunchAgent consuming a job
# queue). This script enqueues the job, then tails the log until it finishes.
#
# Usage: scripts/deploy-device.sh [device-name]   (default: UFIPhone)
set -euo pipefail

APPDIR="$(cd "$(dirname "$0")/.." && pwd)"
RUNNER="$HOME/dev/craft-signing-runner"
DEVICE_NAME="${1:-UFIPhone}"

case "$DEVICE_NAME" in
  UFIPhone)
    XCODE_DEST_ID="00008150-000965113C78401C"
    COREDEVICE_ID="56C18019-B59E-5E29-8F9A-44C3D5D1A58E"
    ;;
  UFIPAD)
    XCODE_DEST_ID="00008112-0015389E2221A01E"
    COREDEVICE_ID="E631940E-1534-507D-8957-D483CCB77E6A"
    ;;
  *)
    echo "unknown device: $DEVICE_NAME (known: UFIPhone, UFIPAD)" >&2
    exit 2
    ;;
esac

job="$(mktemp)"
cat > "$job" <<EOF
set -euo pipefail
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd "$APPDIR"
xcodegen generate
xcodebuild -project Folia.xcodeproj -scheme Folia-iOS -configuration Debug \\
  -destination 'platform=iOS,id=$XCODE_DEST_ID' \\
  -derivedDataPath build/device \\
  -allowProvisioningUpdates -allowProvisioningDeviceRegistration \\
  build
APP="build/device/Build/Products/Debug-iphoneos/Folia.app"
xcrun devicectl device install app --device $COREDEVICE_ID "\$APP"
xcrun devicectl device process launch --device $COREDEVICE_ID com.ufii4.folia-ios
EOF

id="$("$RUNNER/enqueue.sh" "folia-deploy-$DEVICE_NAME" "$job")"
rm -f "$job"
dir="$RUNNER/jobs/$id"
echo "deploy job: $id"

last=0
for i in $(seq 1 1800); do
  if [ -f "$dir/log.txt" ]; then
    lines="$(wc -l < "$dir/log.txt")"
    if [ "$lines" -gt "$last" ]; then
      tail -n "+$((last + 1))" "$dir/log.txt" | sed 's/^/  /'
      last="$lines"
    fi
  fi
  if [ -f "$dir/exit-code.txt" ]; then
    code="$(cat "$dir/exit-code.txt")"
    echo "deploy exit: $code"
    exit "$code"
  fi
  sleep 1
done
echo "timed out waiting for signing runner" >&2
exit 1
