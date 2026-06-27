# Building Typee

Typee is a plain **Swift Package Manager** app — no Xcode project. You only need
the **Xcode Command Line Tools**:

```bash
xcode-select --install
```

## Build & run

```bash
bash build-app.sh      # compiles, bundles, signs, and writes Typee.app
open Typee.app
```

Double-click `Typee.app`, or drag it to `/Applications` to install it permanently.

> **Why a bundle and not the bare binary?** Running as a proper `.app` lets macOS
> track the Accessibility permission by the app's code identity, so the grant
> persists across rebuilds. `build-app.sh` signs local dev builds with a stable
> self-signed certificate (created automatically on first run) to keep that grant
> sticky. Distribution builds (`DIST=1`) are ad-hoc signed instead, so they run on
> any Mac without depending on your keychain.

## Quick dev loop

```bash
swift build && .build/arm64-apple-macosx/debug/Typee
```

The bare debug binary gets a new code identity each rebuild, so macOS re-asks for
Accessibility every time. Use the `.app` bundle above to avoid that.

## Versioning

`kAppVersion` in `Sources/Typee/AppVersion.swift` is the **single source of truth**.
`build-app.sh` and `release.sh` read the version from it — don't hardcode it
anywhere else.

## Cutting a release

Releases are fully automated by `release.sh`. It builds a **universal**
(Apple Silicon + Intel), ad-hoc-signed app, packages a styled DMG, tags the
commit, publishes a GitHub Release with the DMG attached, and refreshes
`latest.json` so the in-app updater points at the new version.

```bash
# 1. Bump the version
#    edit Sources/Typee/AppVersion.swift → kAppVersion = "1.1.0"
# 2. Add a section to CHANGELOG.md
# 3. Commit those changes
git commit -am "Bump to 1.1.0"
# 4. Ship it
./release.sh
```

Prerequisites: the [GitHub CLI](https://cli.github.com) (`gh`) authenticated with
push access to the repo.

### What the scripts do

| Script | Purpose |
|--------|---------|
| `build-app.sh` | Compile + bundle + sign `Typee.app`. `DIST=1` → universal, ad-hoc. |
| `Scripts/generate-icon.swift` | Render the app icon (`Typee.icns`). |
| `Scripts/generate-dmg-background.swift` | Render the DMG background image. |
| `Scripts/make-dmg.sh` | Package a styled `dist/Typee-<version>.dmg`. |
| `release.sh` | Build → DMG → tag → GitHub Release → update `latest.json`. |
