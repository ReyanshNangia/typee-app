#!/bin/bash
set -e
cd "$(dirname "$0")"

# ── Version ───────────────────────────────────────────────────────────────────
# Single source of truth: kAppVersion in Sources/Typee/AppVersion.swift.
VERSION=$(grep 'let kAppVersion' Sources/Typee/AppVersion.swift \
            | sed -E 's/.*"([^"]+)".*/\1/')
VERSION="${VERSION:-1.0.0}"
# ─────────────────────────────────────────────────────────────────────────────
#
# DIST=1 builds a universal (arm64 + x86_64), ad-hoc-signed bundle for
# distribution (used by release.sh). Without it, we build for the host arch and
# sign with the stable local cert so the dev's Accessibility grant persists.

# ── Local signing identity ────────────────────────────────────────────────────
# We sign with a stable local certificate so TCC (accessibility permissions)
# tracks by certificate identity rather than binary hash. This means the
# accessibility grant survives every rebuild — grant it once per Mac, done.
#
# The certificate is created automatically on first build and stored in your
# login keychain. 10-year validity, never leaves this Mac.
CERT_NAME="TypeeLocalSign"
TMPDIR_LOCAL="$HOME/.cache/typee-build"

ensure_signing_identity() {
    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
        return 0
    fi

    echo "→ Creating local signing certificate '$CERT_NAME' (one-time setup)…"
    mkdir -p "$TMPDIR_LOCAL"

    local cfg="$TMPDIR_LOCAL/cert.conf"
    local key="$TMPDIR_LOCAL/typee.key"
    local crt="$TMPDIR_LOCAL/typee.crt"
    local p12="$TMPDIR_LOCAL/typee.p12"

    cat > "$cfg" << 'EOF'
[req]
distinguished_name = dn
x509_extensions    = ext
prompt             = no
[dn]
CN = TypeeLocalSign
[ext]
keyUsage         = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
EOF

    openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
        -keyout "$key" -out "$crt" -config "$cfg" 2>/dev/null

    # OpenSSL 3 changed PKCS12 defaults; use legacy ciphers macOS security accepts
    openssl pkcs12 -export -out "$p12" \
        -inkey "$key" -in "$crt" -passout pass:typee \
        -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg SHA1 2>/dev/null

    security import "$p12" -P typee \
        -k ~/Library/Keychains/login.keychain-db \
        -T /usr/bin/codesign -A 2>/dev/null || true

    # Trust the cert for code signing
    security add-trusted-cert -d -r trustRoot \
        -k ~/Library/Keychains/login.keychain-db "$crt" 2>/dev/null || true

    rm -f "$cfg" "$key" "$p12"  # keep .crt in case trust needs re-applying

    if security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$CERT_NAME\""; then
        echo "  ✓ Certificate created and trusted."
    else
        echo "  ⚠ Could not create certificate — falling back to ad-hoc signing."
        echo "    Accessibility permission will need to be re-granted after each rebuild."
        CERT_NAME="-"
    fi
}

# Distribution builds are ad-hoc signed, so the local cert isn't needed.
[ "${DIST:-0}" = "1" ] || ensure_signing_identity
# ─────────────────────────────────────────────────────────────────────────────

# ── App icon ─────────────────────────────────────────────────────────────────
# Generate the icon once (or whenever the script changes).
if [ ! -f "Typee.icns" ]; then
    echo "→ Generating app icon…"
    swift Scripts/generate-icon.swift 2>/dev/null
    if [ -d "Typee.iconset" ]; then
        iconutil -c icns Typee.iconset -o Typee.icns 2>/dev/null && \
            rm -rf Typee.iconset && echo "  ✓ Icon generated."
    fi
fi
# ─────────────────────────────────────────────────────────────────────────────

SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk
[ -d "$SDK" ] || SDK=$(xcrun --show-sdk-path 2>/dev/null)

if [ "${DIST:-0}" = "1" ]; then
    # Universal build. `swift build --arch a --arch b` needs full Xcode, which
    # may be absent; build each slice separately and lipo them — works with just
    # the Command Line Tools.
    echo "→ Building Typee ${VERSION} (release · universal arm64 + x86_64)…"
    echo "  • arm64…"
    SDKROOT="$SDK" swift build -c release --arch arm64  2>&1 | grep -Ev "^$|^warning:" || true
    echo "  • x86_64… (cross-compile, slower)"
    SDKROOT="$SDK" swift build -c release --arch x86_64 2>&1 | grep -Ev "^$|^warning:" || true
    BIN=".build/universal-Typee"
    lipo -create -output "$BIN" \
        .build/arm64-apple-macosx/release/Typee \
        .build/x86_64-apple-macosx/release/Typee
else
    echo "→ Building Typee ${VERSION} (release)…"
    SDKROOT="$SDK" swift build -c release 2>&1 | grep -Ev "^$|^warning:"
    BIN=".build/arm64-apple-macosx/release/Typee"
fi

APP="Typee.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/Typee"
[ -f "Typee.icns" ] && cp Typee.icns "$APP/Contents/Resources/Typee.icns"

cat > "$APP/Contents/Info.plist" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>        <string>Typee</string>
    <key>CFBundleIdentifier</key>        <string>com.typee.app</string>
    <key>CFBundleName</key>              <string>Typee</string>
    <key>CFBundleDisplayName</key>       <string>Typee</string>
    <key>CFBundleVersion</key>           <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key><string>${VERSION}</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>LSUIElement</key>               <true/>
    <key>NSPrincipalClass</key>          <string>NSApplication</string>
    <key>LSMinimumSystemVersion</key>    <string>13.0</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>NSSupportsAutomaticTermination</key><false/>
    <key>CFBundleIconFile</key>           <string>Typee</string>
    <key>NSHumanReadableCopyright</key>  <string>© 2026 Reyansh Nangia. Made with love.</string>
</dict>
</plist>
PLIST

# Distribution: ad-hoc sign so the bundle is reproducible on any Mac (no
# dependency on this machine's keychain). Local dev: prefer the stable local
# cert (keeps TCC stable across rebuilds), falling back to ad-hoc.
if [ "${DIST:-0}" = "1" ]; then
    echo "→ Signing (ad-hoc · for distribution)…"
    codesign --sign "-" --force --deep --identifier "com.typee.app" "$APP"
else
    echo "→ Signing…"
    codesign --sign "$CERT_NAME" --force --deep \
        --identifier "com.typee.app" \
        "$APP" 2>/dev/null || \
    codesign --sign "-" --force --deep \
        --identifier "com.typee.app" \
        "$APP"
fi

# Strip quarantine — Gatekeeper only applies to quarantined downloads.
# Our locally-built app never needs quarantine.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true

echo ""
echo "✓ Typee.app ${VERSION} is ready in: $(pwd)/Typee.app"
codesign -dv "$APP" 2>&1 | grep -E "^(Identifier|Signature)" | sed 's/^/  /'
echo ""
echo "  • Double-click Typee.app to launch"
echo "  • Drag to /Applications to install permanently"
echo "  • Grant Accessibility once in System Settings — it persists across rebuilds"
echo ""
echo "  To cut a public release:"
echo "    1. Bump kAppVersion in Sources/Typee/AppVersion.swift"
echo "    2. Add notes to CHANGELOG.md"
echo "    3. Run ./release.sh — builds universal, makes the DMG,"
echo "       tags, publishes the GitHub release, and updates the auto-updater."
