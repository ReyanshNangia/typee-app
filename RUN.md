# Typee

## One-time setup (already done if you ran the sudo mv)

```bash
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.bak
```

## Build

```bash
cd ~/Desktop/typee-claude
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build
```

## Run

```bash
.build/arm64-apple-macosx/debug/Typee
```

The app has no Dock icon. Look for the pencil icon in the menu bar.
Double-press Control to show/hide the window.

## Rebuild after code changes

```bash
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build && .build/arm64-apple-macosx/debug/Typee
```
