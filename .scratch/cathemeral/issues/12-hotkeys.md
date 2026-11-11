# 12: Hotkeys

**What to build:** Global hotkeys, chosen by the user in Settings, with none bound by default. Level up and level down step the frontmost app's level by 10% with a 150 ms ramp and save it, creating an app setting if the app had none. If the frontmost app is an ignored app, a level hotkey does nothing. An on/off hotkey toggles all of Cathemeral. A level hotkey shows a small indicator ("Notion 40%") for 1 s on the affected display. Hotkeys use an API that needs no Accessibility permission.

**Blocked by:** 11 (Settings window and Apps list)

**Status:** ready-for-human

- [x] A fresh install has no hotkeys bound.
- [ ] The user can bind, change and clear each hotkey in Settings, and bindings survive a restart.
- [ ] Level down on Notion at 40% takes it to 30% with a ramp, and the indicator appears on Notion's display.
- [ ] Levels never go below 10% or above 100% through hotkeys.
- [ ] A level hotkey with Spotlight frontmost changes nothing.
- [ ] The on/off hotkey toggles dimming on every display.
- [x] DimmingEngine tests cover a nudge on the frontmost app, creating a missing app setting, clamping, and the ignored-app no-op.

## Comments

### 2026-11-11: implemented (agent)

- **Engine:** `DimmingEngine.nudgeLevel(of:_:)` steps the app's level by 10%, rounded to a whole percent (0.4 − 0.1 isn't 0.3 in binary, so unrounded steps drift), and saves it as its app setting, starting from the default level if it had none. Every display the app owns fades over `switchRamp`. Levels are clamped by `Level`. An ignored app returns nil and changes nothing. Mid-switch it never brightens a display dimmed early (`isHeldForSwitch`, now shared with `applySettings`). With the master switch off, the level still saves for later (per CONTEXT.md) and the indicator still shows.
- **Bindings** live in `Settings.hotkeys` (`HotkeyAction` → `Hotkey`: key code + modifiers). `FileSettingsStore` schema 3 saves them as `{"action", "keyCode", "modifiers"}`; an older file loads with none, and an action or modifier this build doesn't know is dropped. `DimmingEngine.setHotkey` binds, changes or clears; binding a combination already used by another action moves it, since one key combination can't do two things.
- **HotkeyService** (BrightnessPlatform) uses Carbon `RegisterEventHotKey`, which needs no Accessibility or Input Monitoring permission. A hotkey macOS refuses (usually held by another app) gets an orange warning in Settings.
- **Settings → General → Hotkeys:** a recorder per action (Level up, Level down, Turn on or off) plus a clear button. Escape cancels. Each hotkey needs ⌘ or ⌃: macOS 15 refuses ⌥-only and ⌥⇧ hotkeys, and a bare key would take over typing. While recording, every hotkey is unregistered, so pressing one that's already bound reaches the recorder.
- **Indicator:** a non-activating, click-through capsule ("Notion 30%"), 12% up from the bottom of the display that changed (the app's front-window display if it owns it, else one it owns, else its front-window display). It stays 1 s after the last press, then fades over 0.2 s.
- `scripts/check` passes (132 tests). `Tools/e2e.sh switching` passes (18 checks). There's no e2e section for hotkeys: a press can't be synthesised without Accessibility permission, which is exactly what the feature avoids.
- **Risk for the Spotlight check:** the engine ignores Spotlight, but the hotkey targets `NSWorkspace.frontmostApplication`. If macOS reports the app behind Spotlight's panel instead of Spotlight, the hotkey would change that app. Check by hand; if it fails, the fix is to look for Spotlight's on-screen window in `Displays.frontmostApp()`.

Left for a human:
- [ ] Bind, change and clear each hotkey in Settings; quit and relaunch, and the bindings are still there.
- [ ] Level down with Notion at 40% fades it to 30%, and "Notion 30%" shows for about 1 s on Notion's display (try it on the external display too).
- [ ] Pressing level down again and again stops at 10%, and level up stops at 100%.
- [ ] With Spotlight open, a level hotkey changes nothing.
- [ ] The on/off hotkey fades every display to 100% and back.
- [ ] A hotkey another app already uses shows the orange warning.

