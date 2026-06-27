#!/bin/bash
# One-command release: build universal → DMG → tag → GitHub Release → update auto-updater.
#
#   1. Bump kAppVersion in Sources/Typee/AppVersion.swift
#   2. Add a section to CHANGELOG.md
#   3. Commit those changes
#   4. ./release.sh
set -e
cd "$(dirname "$0")"

VERSION=$(grep 'let kAppVersion' Sources/Typee/AppVersion.swift \
            | sed -E 's/.*"([^"]+)".*/\1/')
TAG="v${VERSION}"
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DMG="dist/Typee-${VERSION}.dmg"

echo "→ Releasing Typee ${VERSION} to ${REPO}"

# ── Preflight ─────────────────────────────────────────────────────────────────
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then
    echo "✗ Working tree has uncommitted changes. Commit them first." >&2
    exit 1
fi
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "✗ Tag $TAG already exists. Bump kAppVersion first." >&2
    exit 1
fi

# ── Build + package ───────────────────────────────────────────────────────────
DIST=1 bash build-app.sh
bash Scripts/make-dmg.sh
SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')

# ── Update the auto-updater feed ──────────────────────────────────────────────
cat > latest.json <<JSON
{
  "version": "${VERSION}",
  "url": "https://github.com/${REPO}/releases/latest"
}
JSON
git add latest.json
if ! git diff --cached --quiet; then
    git commit -m "Release ${TAG}" >/dev/null
    git push origin HEAD
fi
git tag "$TAG"
git push origin "$TAG"

# ── Release notes from CHANGELOG ──────────────────────────────────────────────
NOTES=$(awk "/^## \[${VERSION}\]/{f=1;next} /^## \[/{f=0} f" CHANGELOG.md)
NOTES_FILE="$(mktemp)"
{
    echo "$NOTES"
    echo ""
    echo "---"
    echo "**SHA-256 (\`Typee-${VERSION}.dmg\`):** \`${SHA}\`"
    echo ""
    echo "### Install"
    echo "1. Download \`Typee-${VERSION}.dmg\` below and open it."
    echo "2. Drag **Typee** onto **Applications**."
    echo "3. First launch: **right-click Typee → Open** (one-time Gatekeeper step)."
    echo "4. Grant **Accessibility** when prompted so the global hotkey works."
} > "$NOTES_FILE"

# ── Publish ───────────────────────────────────────────────────────────────────
gh release create "$TAG" "$DMG" \
    --repo "$REPO" \
    --title "Typee ${VERSION}" \
    --notes-file "$NOTES_FILE"
rm -f "$NOTES_FILE"

echo ""
echo "✓ Released ${TAG}: https://github.com/${REPO}/releases/tag/${TAG}"
