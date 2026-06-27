#!/bin/bash
# Builds a styled, compressed Typee-<version>.dmg in dist/.
# Self-contained (hdiutil + AppleScript); no external dependencies required.
set -e
cd "$(dirname "$0")/.."

VERSION=$(grep 'let kAppVersion' Sources/Typee/AppVersion.swift \
            | sed -E 's/.*"([^"]+)".*/\1/')
VERSION="${VERSION:-1.0.0}"

APP="Typee.app"
VOL="Typee"
DMG="dist/Typee-${VERSION}.dmg"
STAGE="$(mktemp -d)"
RW="$(mktemp -u).dmg"
MNT="/Volumes/${VOL}"

if [ ! -d "$APP" ]; then
    echo "✗ $APP not found. Run: DIST=1 bash build-app.sh" >&2
    exit 1
fi

cleanup() {
    hdiutil detach "$MNT" >/dev/null 2>&1 || true
    rm -rf "$STAGE" "$RW"
}
trap cleanup EXIT

# If a stale Typee volume is mounted, unmount it.
hdiutil detach "$MNT" >/dev/null 2>&1 || true

echo "→ Generating DMG background…"
if [ ! -f "Scripts/dmg-background.png" ]; then
    swift Scripts/generate-dmg-background.swift >/dev/null 2>&1 || true
fi

# Stage contents: app + Applications shortcut + background + volume icon
mkdir -p "$STAGE/.background"
ditto "$APP" "$STAGE/$APP"
ln -s /Applications "$STAGE/Applications"
if [ -f "Scripts/dmg-background@2x.png" ]; then
    # Combine 1x/2x into a HiDPI-aware tiff so Retina stays crisp.
    tiffutil -cathidpicheck Scripts/dmg-background.png Scripts/dmg-background@2x.png \
        -out "$STAGE/.background/background.tiff" >/dev/null 2>&1 \
        || cp Scripts/dmg-background.png "$STAGE/.background/background.tiff"
else
    cp Scripts/dmg-background.png "$STAGE/.background/background.tiff" 2>/dev/null || true
fi

# Create a writable DMG from the staging dir (with slack for .DS_Store and the
# volume icon), then style it.
echo "→ Creating writable image…"
SIZE_MB=$(( $(du -sm "$STAGE" | cut -f1) + 60 ))
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ \
    -size "${SIZE_MB}m" -format UDRW -ov "$RW" >/dev/null
hdiutil attach "$RW" -mountpoint "$MNT" -nobrowse -noautoopen >/dev/null

echo "→ Applying Finder layout…"
osascript <<APPLESCRIPT 2>/dev/null || echo "  ⚠ Finder styling skipped (DMG still valid)."
tell application "Finder"
    tell disk "${VOL}"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 150, 820, 570}
        set vopts to the icon view options of container window
        set arrangement of vopts to not arranged
        set icon size of vopts to 112
        set background picture of vopts to file ".background:background.tiff"
        set position of item "${APP}" of container window to {165, 205}
        set position of item "Applications" of container window to {455, 205}
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Give the volume a custom icon — written last so the Finder styling pass
# (which rewrites volume metadata) can't drop it. srcfolder also strips
# root-level hidden files, so this must be done in-place on the mounted image.
if [ -f "Typee.icns" ]; then
    cp "Typee.icns" "$MNT/.VolumeIcon.icns"
    SetFile -a C "$MNT" 2>/dev/null || true
fi

sync
hdiutil detach "$MNT" >/dev/null 2>&1 || true

echo "→ Compressing…"
mkdir -p dist
rm -f "$DMG"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" >/dev/null

echo ""
echo "✓ $DMG ($(du -h "$DMG" | cut -f1))"
shasum -a 256 "$DMG" | sed 's/^/  SHA-256: /'
