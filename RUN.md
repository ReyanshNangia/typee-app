# How to Run Typee

## Every time you want to run an updated version

Do these steps in order:

**Step 1 — Open Terminal**
Open the Terminal app on your Mac.

**Step 2 — Close the old version (if it's running)**
Type this and press Enter:
```
pkill Typee
```
If it says "No matching processes", that's fine — it just means it wasn't running.

**Step 3 — Go to the project folder**
```
cd ~/Desktop/typee-claude
```

**Step 4 — Build and run**
```
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build && .build/arm64-apple-macosx/debug/Typee
```
Wait for it to say `Build complete!`, then the app is running.

**Step 5 — Find the app**
Look for the ✏️ pencil icon in your menu bar (top right of screen).
Double-press the Control key to show or hide the window.

---

## One command (shortcut for steps 2–4)

Once you know the steps, you can do it all in one go:
```
pkill Typee; cd ~/Desktop/typee-claude && SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk swift build && .build/arm64-apple-macosx/debug/Typee
```

---

## One-time setup (already done — don't do this again)

This was run once to fix a Mac tooling conflict. You never need to do it again:
```
sudo mv /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap \
        /Library/Developer/CommandLineTools/usr/include/swift/module.modulemap.bak
```
