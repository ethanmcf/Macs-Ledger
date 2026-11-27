#!/bin/bash
# Builds Mac's Ledger and installs it on your iPhone over Wi-Fi, before its signing profile expires.
#
# An installed app stops opening when the provisioning profile it was signed with expires (7 days for a
# free Personal Team). Reinstalling only helps if the new build has a *newer* profile, so this script
# decides everything from real expiry dates:
#   - It reinstalls once the installed app has RENEW_DAYS_LEFT days or fewer left. With a 7-day profile
#     that's 3 days after each install, leaving ~4 days of hourly retries.
#   - It never trusts more than MAX_PROFILE_DAYS from a build, even if the profile claims longer (a profile
#     left over from an old paid membership can say 1 year; a Personal Team only gets 7 days).
#   - Before rebuilding, it clears Xcode's cached profile for this app, so Xcode fetches a fresh one
#     instead of reusing the old one.
# Run it by hand, or let the launch job run it every hour (scripts/install-schedule.sh).
#
# Usage:
#   ./scripts/install-on-phone.sh           # install if due
#   ./scripts/install-on-phone.sh --force   # install now
#
# Needs:
#   - IPHONE_UDID in .env at the repo root (see .env.example)
#   - Your Apple ID signed in to Xcode (Settings → Accounts)
#   - The phone paired with "Connect via network" on (Xcode → Window → Devices and Simulators),
#     and on the same Wi-Fi as this Mac
set -euo pipefail

# launchd starts jobs with a minimal environment; make sure xcrun/xcodebuild are found.
export PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$ROOT/.env"
BUILD_DIR="${TMPDIR:-/tmp}/macs-ledger-build"
APP="$BUILD_DIR/Build/Products/Release-iphoneos/macs-ledger.app"
STATE_DIR="$HOME/Library/Application Support/macs-ledger"
INSTALLED_EXPIRY="$STATE_DIR/installed-profile-expiry"   # epoch seconds, written after each install
PROFILE_DIRS=("$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles" "$HOME/Library/MobileDevice/Provisioning Profiles")

RENEW_DAYS_LEFT=4   # reinstall when the installed app has this many days or fewer left
MAX_PROFILE_DAYS=7  # free Personal Team profiles last 7 days; never assume a build lasts longer

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"; }
now() { date +%s; }
days_left() { echo $(( ($1 - $(now)) / 86400 )); }
show_date() { date -r "$1" '+%b %-d %H:%M'; }

# Expiry (epoch seconds) of the provisioning profile file given, or of an .app's embedded profile.
profile_expiry() {
    local file="$1"
    [[ -d "$file" ]] && file="$file/embedded.mobileprovision"
    [[ -f "$file" ]] || { echo 0; return; }
    local iso
    iso="$(security cms -D -i "$file" 2>/dev/null | plutil -extract ExpirationDate raw -o - - 2>/dev/null)" || { echo 0; return; }
    date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$iso" +%s 2>/dev/null || echo 0
}

# When a built .app should be treated as expiring: its profile's date, but no later than
# MAX_PROFILE_DAYS after it was built. 0 if there's no build.
build_expiry_of() {
    local app="$1" profile built cap
    profile="$(profile_expiry "$app")"
    (( profile > 0 )) || { echo 0; return; }
    built="$(stat -f %m "$app")"
    cap=$(( built + MAX_PROFILE_DAYS * 86400 ))
    echo $(( profile < cap ? profile : cap ))
}

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# 1. Is a reinstall due? Based on when the installed app's profile actually expires.
if ! $FORCE && [[ -f "$INSTALLED_EXPIRY" ]]; then
    expires="$(cat "$INSTALLED_EXPIRY")"
    if (( $(days_left "$expires") > RENEW_DAYS_LEFT )); then
        log "Installed app is good until $(show_date "$expires") ($(days_left "$expires") days left). Nothing to do."
        exit 0
    fi
    log "Installed app expires $(show_date "$expires") ($(days_left "$expires") days left). Renewing."
fi

# 2. Settings
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

# 3. Is the phone reachable right now? (Cheap check before a build.) `devicectl device info` answers from
#    saved pairing info even when the phone is away, so read the live State column instead.
DEVICE_ROW="$(xcrun devicectl list devices 2>/dev/null | grep -i -- "$IPHONE_UDID" || true)"
if [[ -z "$DEVICE_ROW" ]]; then
    log "No paired device matches IPHONE_UDID in .env. Check it with: xcrun devicectl list devices"
    exit 1
fi
if grep -q "unavailable" <<< "$DEVICE_ROW"; then
    log "iPhone isn't reachable right now (asleep, or not on this Wi-Fi). Will try again next run."
    exit 2
fi

# 4. Build, unless the last build is still fresh (e.g. it was built but the phone went away).
build_expiry="$(build_expiry_of "$APP")"
if (( build_expiry > 0 )) && (( $(days_left "$build_expiry") > RENEW_DAYS_LEFT )); then
    log "Reusing existing build (good until $(show_date "$build_expiry"))."
else
    # Xcode keeps using a cached profile until it expires. Remove this app's cached profiles so the
    # build gets a fresh one with a full expiry period.
    BUNDLE_ID="$(grep -m1 'PRODUCT_BUNDLE_IDENTIFIER' "$ROOT/macs-ledger.xcodeproj/project.pbxproj" | sed -E 's/.*= "?([^";]+)"?;.*/\1/')"
    for dir in "${PROFILE_DIRS[@]}"; do
        [[ -d "$dir" ]] || continue
        for profile in "$dir"/*.mobileprovision; do
            [[ -f "$profile" ]] || continue
            app_id="$(security cms -D -i "$profile" 2>/dev/null | plutil -extract Entitlements.application-identifier raw -o - - 2>/dev/null || true)"
            if [[ "$app_id" == *".$BUNDLE_ID" ]]; then
                rm -f "$profile"
                log "Cleared cached profile $(basename "$profile")."
            fi
        done
    done

    log "Building…"
    # -allowProvisioningUpdates lets Xcode fetch the new profile.
    xcodebuild \
        -project "$ROOT/macs-ledger.xcodeproj" \
        -scheme macs-ledger \
        -configuration Release \
        -destination 'generic/platform=iOS' \
        -derivedDataPath "$BUILD_DIR" \
        -allowProvisioningUpdates \
        -quiet \
        build
    touch "$APP" # the build time caps how long this build is trusted (MAX_PROFILE_DAYS)
    profile_date="$(profile_expiry "$APP")"
    build_expiry="$(build_expiry_of "$APP")"
    if (( profile_date > build_expiry )); then
        log "New build's profile says $(show_date "$profile_date"), but treating it as $MAX_PROFILE_DAYS days: good until $(show_date "$build_expiry")."
    else
        log "New build's profile is good until $(show_date "$build_expiry") ($(days_left "$build_expiry") days)."
    fi
    if (( $(days_left "$build_expiry") <= RENEW_DAYS_LEFT )); then
        log "WARNING: Xcode didn't issue a fresh profile, so installing won't extend the app's life. Open the project in Xcode once and check Signing & Capabilities."
    fi
fi

# 5. Install.
log "Installing on iPhone…"
if ! xcrun devicectl device install app --device "$IPHONE_UDID" "$APP"; then
    log "Install failed. If the phone was locked or asleep, it'll be retried next run."
    exit 3
fi

mkdir -p "$STATE_DIR"
echo "$build_expiry" > "$INSTALLED_EXPIRY"
log "Done. The app on your phone is good until $(show_date "$build_expiry"). Renewing when $RENEW_DAYS_LEFT days are left."
