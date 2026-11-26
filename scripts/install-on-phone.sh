#!/usr/bin/env bash
# Builds Mac's Ledger and installs it on your iPhone over Wi-Fi.
#
# Apps signed with a free Apple ID expire after 7 days; reinstalling resets that and keeps your data.
# Run it by hand, or on a schedule (launchd) every few days.
#
# Needs:
#   - IPHONE_UDID in .env at the repo root (see .env.example)
#   - Your Apple ID signed in to Xcode (Settings → Accounts)
#   - The phone paired with "Connect via network" on (Xcode → Window → Devices and Simulators),
#     and on the same Wi-Fi as this Mac
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
BUILD_DIR="${TMPDIR:-/tmp}/macs-ledger-build"
APP="$BUILD_DIR/Build/Products/Release-iphoneos/macs-ledger.app"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }

if [[ ! -f "$ENV_FILE" ]]; then
    log "Missing $ENV_FILE. Copy .env.example to .env and set IPHONE_UDID."
    exit 1
fi
set -a
# shellcheck source=/dev/null
source "$ENV_FILE"
set +a
if [[ -z "${IPHONE_UDID:-}" ]]; then
    log "IPHONE_UDID is empty in $ENV_FILE."
    exit 1
fi

# Fail early (and clearly) if the phone isn't reachable, instead of after a full build.
if ! xcrun devicectl device info details --device "$IPHONE_UDID" >/dev/null 2>&1; then
    log "iPhone $IPHONE_UDID isn't reachable. Is it on the same Wi-Fi with 'Connect via network' on?"
    exit 2
fi

log "Building…"
# -allowProvisioningUpdates lets Xcode renew the free 7-day provisioning profile.
xcodebuild \
    -project "$ROOT/macs-ledger.xcodeproj" \
    -scheme macs-ledger \
    -configuration Release \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$BUILD_DIR" \
    -allowProvisioningUpdates \
    -quiet \
    build

log "Installing on iPhone…"
xcrun devicectl device install app --device "$IPHONE_UDID" "$APP"

log "Done. Installed $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP/Info.plist") on $IPHONE_UDID."
