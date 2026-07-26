#!/bin/zsh
set -e
cd "$(dirname "$0")"

echo "Building QuotaBar (release)..."
swift build -c release

APP="QuotaBar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/QuotaBar "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"

if [[ "$1" == "--install" ]]; then
    pkill -x QuotaBar 2>/dev/null || true
    sleep 1
    rm -rf /Applications/"$APP"
    ditto "$APP" /Applications/"$APP"
    echo "Installed to /Applications/$APP"
    open -a /Applications/$APP
    echo "Launched. Look for the rings in your menu bar."
    echo "Note: macOS will ask once to allow Keychain access for Claude credentials — click Always Allow."
fi
