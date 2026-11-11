---
name: install-cathemeral
description: Build Cathemeral from this clone and install it into /Applications. Use when the user asks to install, set up, update or reinstall the app, or uninstall it.
---

# Install Cathemeral

There is no signed release (ticket 13 is wontfix), so installing means building the Release app from source and copying it into `/Applications`. Run every command from the repo root. The README's "Install" section has the same steps for people.

Each step ends on its check. Stop at the first failing check, tell the user what failed and the fix, and wait for them.

## Steps

1. **macOS 14 or later.** `sw_vers -productVersion` prints 14.0 or higher.

2. **Full Xcode selected.** `xcodebuild -version` prints `Xcode 16` or later.
   - If it fails or `xcode-select -p` points at `/Library/Developer/CommandLineTools`, Xcode is missing or not selected. These need the user (App Store install, `sudo`): ask them to install Xcode from the App Store, then run `! sudo xcode-select -s /Applications/Xcode.app/Contents/Developer`.
   - If it asks for the licence, ask them to run `! sudo xcodebuild -license accept`.

3. **No Cathemeral running.** Two copies would both write gamma. Quit any running copy (it restores the screen as it quits):
   ```sh
   osascript -e 'quit app id "io.github.ravi-03.cathemeral"'
   ```
   Check: `pgrep -x Cathemeral` prints nothing.

4. **Release build.** This takes a minute or two on a clean clone:
   ```sh
   xcodebuild -project Cathemeral.xcodeproj -scheme Cathemeral -configuration Release \
       -destination "platform=macOS,arch=$(uname -m)" -derivedDataPath build/DerivedData -quiet build
   ```
   The `Supported platforms for the buildables in the current scheme is empty` line is harmless. Check: the command exits 0 and `build/DerivedData/Build/Products/Release/Cathemeral.app/Contents/MacOS/GammaWatchdog` is executable. Without the watchdog the safety net can't restore the screen if the app dies.

5. **Copied into /Applications.** If `/Applications/Cathemeral.app` exists, this replaces it: tell the user before you remove it. Their settings live outside the app (`~/Library/Application Support/Cathemeral/settings.json`) and survive.
   ```sh
   rm -rf /Applications/Cathemeral.app
   ditto build/DerivedData/Build/Products/Release/Cathemeral.app /Applications/Cathemeral.app
   ```
   Check: `codesign -v /Applications/Cathemeral.app` exits 0.

6. **Running.** `open /Applications/Cathemeral.app`. Check: `pgrep -x Cathemeral` prints a pid.

Then tell the user: the app has no Dock icon, only a menu bar icon. Click it for the popover (levels, default level, Launch at login), and right-click it for Enable/Disable, Settings and Quit. If the screen ever stays dim, the README's "If your screen is stuck dim" section has the fixes.

## Uninstall

Quit it (step 3), then `rm -rf /Applications/Cathemeral.app`. Ask before also deleting the settings in `~/Library/Application Support/Cathemeral`. If Launch at login was on and System Settings → General → Login Items still lists Cathemeral, the user can remove it there.
