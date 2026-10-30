#!/bin/sh
# Build Tray.app: release build → bundle → codesign → print the path.
# Signs with the first valid "Apple Development" identity (override: TRAY_SIGN_IDENTITY=<name or SHA-1>).
set -eu
cd "$(dirname "$0")/.."

swift build -c release
BIN="$(swift build -c release --show-bin-path)/Tray"
APP=build/Tray.app

mkdir -p "$APP/Contents/MacOS"
cp "$BIN" "$APP/Contents/MacOS/Tray"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key><string>dev.illia.tray</string>
    <key>CFBundleName</key><string>Tray</string>
    <key>CFBundleExecutable</key><string>Tray</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

# SHA-1 instead of the name: two valid certs with the same name make codesign fail as ambiguous.
IDENTITY="${TRAY_SIGN_IDENTITY:-$(security find-identity -v -p codesigning | awk '/"Apple Development/ { print $2; exit }')}"
if [ -n "$IDENTITY" ]; then
    codesign --force --sign "$IDENTITY" "$APP"
else
    cat >&2 <<'WARN'

!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
!! WARNING: no "Apple Development" signing identity found. Signing AD-HOC.          !!
!! Every build gets a new signature: macOS silently revokes Accessibility and        !!
!! Screen Recording for Tray. Re-grant them after each build, or install your        !!
!! Apple Development certificate (Xcode → Settings → Accounts).                      !!
!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

WARN
    codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"

echo "$PWD/$APP"
