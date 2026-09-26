#!/bin/bash
#
# Builds Halo.app, its now-playing helper, and the Halo page for System Settings.
#
#   Scripts/build-app.sh            build into build/
#   Scripts/build-app.sh install    build, install to /Applications and
#                                   ~/Library/PreferencePanes, and relaunch
#
# No Xcode project: this builds with the Command Line Tools alone.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Assembled outside the project: iCloud-synced folders (like ~/Documents) tag
# files with Finder metadata that codesign refuses to sign over.
STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Halo.app"
PANE="$STAGE/Halo.prefPane"
VERSION="2.0.0"

cd "$ROOT"
echo "Building Halo…"
swift build -c release --product Halo
BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Halo" "$APP/Contents/MacOS/Halo"

echo "Building now-playing helper…"
clang -dynamiclib -fobjc-arc -O2 -Wall -Werror \
    -arch arm64 -arch x86_64 \
    -mmacosx-version-min=26.0 \
    -framework Foundation \
    -F/System/Library/PrivateFrameworks -framework MediaRemote \
    "$ROOT/Helper/HaloMedia.m" \
    -o "$APP/Contents/Resources/libHaloMedia.dylib"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>                  <string>Halo</string>
    <key>CFBundleDisplayName</key>           <string>Halo</string>
    <key>CFBundleExecutable</key>            <string>Halo</string>
    <key>CFBundleIdentifier</key>            <string>com.niranjan.Halo</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>CFBundlePackageType</key>           <string>APPL</string>
    <key>LSMinimumSystemVersion</key>        <string>26.0</string>
    <key>LSUIElement</key>                   <true/>
    <key>NSHighResolutionCapable</key>       <true/>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>Halo shows AirPods and other Bluetooth devices in Halo when they connect.</string>
    <key>NSDesktopFolderUsageDescription</key>
    <string>Halo puts new screenshots on the Shelf so you can drag them anywhere.</string>
    <key>NSAppleEventsUsageDescription</key>
    <string>Halo controls Music for song actions, System Events for Dark Mode and the Dock, and Finder to empty the Trash — only when you ask.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>Halo uses your location to show the weather for where you are.</string>
    <key>NSCalendarsFullAccessUsageDescription</key>
    <string>Halo shows your next event in Halo as it approaches.</string>
    <key>NSRemindersFullAccessUsageDescription</key>
    <string>Halo shows your reminders in Halo so you can tick them off and add new ones.</string>
    <key>NSCameraUsageDescription</key>
    <string>Halo's Mirror page shows your camera so you can check how you look before a call. Nothing is recorded.</string>
    <key>NSDownloadsFolderUsageDescription</key>
    <string>Halo shows AirDrop transfers and finished downloads in Halo.</string>
</dict>
</plist>
PLIST
# macOS ties Accessibility (and the other privacy permissions) to the app's code
# signature. Ad-hoc signing has no stable identity, so the grant is pinned to that
# one build and silently stops matching the next time this script runs: the app
# stays ticked in Privacy & Security while AXIsProcessTrusted() returns false.
#
# Signing with a real identity keeps the grant across rebuilds. Set HALO_SIGN_IDENTITY
# to one from `security find-identity -v -p codesigning`, or leave it unset to carry
# on ad-hoc and re-tick the permission after each build.
SIGN_IDENTITY="${HALO_SIGN_IDENTITY:--}"
if [ "$SIGN_IDENTITY" = "-" ]; then
    echo "note: signing ad-hoc. Accessibility permission will need re-granting after this build."
    echo "      Set HALO_SIGN_IDENTITY to a codesigning identity to keep it across rebuilds."
fi

codesign --force --deep --sign "$SIGN_IDENTITY" "$APP"

echo "Building System Settings page…"
mkdir -p "$PANE/Contents/MacOS" "$PANE/Contents/Resources"
# A preference pane is a loadable bundle, so it is linked directly with swiftc
# rather than as a SwiftPM dylib. It shares HaloCore's sources with the app.
# Compiled as one module, so the pane's `import HaloCore` is dropped.
mkdir -p "$STAGE/pane-src"
sed '/^import HaloCore$/d' "$ROOT/Sources/HaloPane/HaloPane.swift" > "$STAGE/pane-src/HaloPane.swift"
swiftc -O -swift-version 5 -target arm64-apple-macosx14.0 \
    -module-name HaloPane -parse-as-library \
    -emit-library -Xlinker -bundle \
    "$ROOT"/Sources/HaloCore/*.swift "$STAGE/pane-src/HaloPane.swift" \
    -o "$PANE/Contents/MacOS/HaloPane" 2>&1 | grep -v "^warning: unable to determine" || true
test -f "$PANE/Contents/MacOS/HaloPane"
"$APP/Contents/MacOS/Halo" --pane-icon "$PANE/Contents/Resources/HaloPane.png"

cat > "$PANE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleIdentifier</key>            <string>com.niranjan.Halo.prefPane</string>
    <key>CFBundleExecutable</key>            <string>HaloPane</string>
    <key>CFBundleName</key>                  <string>Halo</string>
    <key>CFBundlePackageType</key>           <string>BNDL</string>
    <key>CFBundleVersion</key>               <string>$VERSION</string>
    <key>CFBundleShortVersionString</key>    <string>$VERSION</string>
    <key>NSPrincipalClass</key>              <string>HaloPreferencePane</string>
    <key>NSPrefPaneIconLabel</key>           <string>Halo</string>
    <key>NSPrefPaneIconFile</key>            <string>HaloPane.png</string>
    <key>LSMinimumSystemVersion</key>        <string>14.0</string>
</dict>
</plist>
PLIST
codesign --force --sign "$SIGN_IDENTITY" "$PANE"

mkdir -p "$ROOT/build"
rm -rf "$ROOT/build/Halo.app" "$ROOT/build/Halo.prefPane"
ditto --norsrc --noextattr "$APP" "$ROOT/build/Halo.app"
ditto --norsrc --noextattr "$PANE" "$ROOT/build/Halo.prefPane"
echo "Built $ROOT/build/Halo.app and Halo.prefPane"

if [[ "${1:-}" == "install" ]]; then
    pkill -x Halo 2>/dev/null || true
    # Wait for it to actually exit: launching while the old copy is still alive makes
    # the new one see a duplicate and quit, leaving no island at all.
    for _ in $(seq 1 40); do
        pgrep -x Halo >/dev/null 2>&1 || break
        sleep 0.25
    done
    # System Settings caches loaded panes; quit it so the new page is picked up.
    osascript -e 'quit app "System Settings"' 2>/dev/null || true
    sleep 0.8
    rm -rf /Applications/Halo.app
    ditto --norsrc --noextattr "$APP" /Applications/Halo.app
    mkdir -p "$HOME/Library/PreferencePanes"
    rm -rf "$HOME/Library/PreferencePanes/Halo.prefPane"
    ditto --norsrc --noextattr "$PANE" "$HOME/Library/PreferencePanes/Halo.prefPane"
    open /Applications/Halo.app
    echo "Installed /Applications/Halo.app and ~/Library/PreferencePanes/Halo.prefPane"
fi
