#!/bin/bash
# Installs (or removes) a launch job that runs install-on-phone.sh when you log in and every hour after.
# install-on-phone.sh only reinstalls once the last install is 3+ days old, so most hourly runs do nothing.
#
# Usage:
#   ./scripts/install-schedule.sh              # install or update the job
#   ./scripts/install-schedule.sh --uninstall  # remove it
#
# Log: ~/Library/Logs/macs-ledger-install.log
set -euo pipefail

LABEL="com.macs-ledger.install-on-phone"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/macs-ledger-install.log"
DOMAIN="gui/$(id -u)"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/install-on-phone.sh"

# Remove any existing job first, so re-running this updates it.
launchctl bootout "$DOMAIN/$LABEL" 2>/dev/null || true

if [[ "${1:-}" == "--uninstall" ]]; then
    rm -f "$PLIST"
    echo "Removed the launch job. (Log left at $LOG)"
    exit 0
fi

mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>$LABEL</string>
    <key>ProgramArguments</key>
    <array>
        <string>/bin/bash</string>
        <string>$SCRIPT</string>
    </array>
    <!-- Run when you log in, then every hour. Runs missed while the Mac slept fire when it wakes. -->
    <key>RunAtLoad</key>
    <true/>
    <key>StartInterval</key>
    <integer>3600</integer>
    <key>StandardOutPath</key>
    <string>$LOG</string>
    <key>StandardErrorPath</key>
    <string>$LOG</string>
</dict>
</plist>
EOF

plutil -lint "$PLIST" >/dev/null
launchctl bootstrap "$DOMAIN" "$PLIST"
echo "Installed. It runs now, at every login, and hourly. Check progress with:"
echo "  tail -f $LOG"
