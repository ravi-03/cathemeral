# 11: Settings window and Apps list

**What to build:** A Settings window, opened from the popover's gear and the right-click menu. Its Apps tab lists every saved app setting alphabetically: icon, name, level slider and a remove button (the same as "Use default"). Apps that are no longer installed appear greyed out. Apps without a bundle ID show by their file name. A slider here behaves like any other: live if its app owns a display, otherwise it only saves. Settings also shows the manual recovery steps for a screen stuck dim, matching the README.

**Blocked by:** 04 (Saved app settings and default level)

**Status:** ready-for-human

- [ ] Every saved app setting appears in the Apps list, including apps that aren't running.
- [ ] Changing a level there takes effect live if the app owns a display, and is saved either way.
- [ ] Remove deletes the app setting, and the app then follows the default level.
- [ ] Uninstalled apps are greyed out.
- [ ] The recovery steps are shown in Settings.

## Comments

### 2026-11-11: implemented (agent)

- **Settings window** has three tabs: General (default level, launch at login), Apps, and Stuck Dim? (recovery steps). It opens from the popover's new gear (next to the master switch) and from the right-click menu's Settings…; both close the popover first.
- **Apps list** (`DimmingEngine.savedApps(installedName:)`): every app setting, sorted by name with `localizedStandardCompare`, whether or not the app is running. App settings are saved without names, so `InstalledApps` (BrightnessPlatform) looks each app up through Launch Services and caches its name and icon until the window is next shown. An app without a bundle ID always shows by its file name (`AppID.fileName`). An uninstalled app with a bundle ID shows by its bundle ID, since nothing else is known about it; it is greyed out with a "Not installed" caption.
- Each row's slider calls `engine.setLevel`, the same as the popover's sliders: live (throttled, no ramp) if the app owns a display, otherwise it only saves. The remove button is `useDefault`, and the row disappears.
- **Recovery steps** live in `RecoverySteps` (BrightnessCore), and `RecoveryStepsTests` checks them line by line against the README's "If your screen is stuck dim" section, so the two can't drift apart.
- `scripts/check` passes (123 tests). `Tools/e2e.sh` passes (62 checks), after quitting the Debug build that was running.
- An app Launch Services can't find, such as one run from a mounted disk image, shows as not installed even while it's running.

Left for a human:
- [ ] The gear and Settings… both open the window; the three tabs look right in light and dark.
- [ ] The Apps list shows every app setting, with icons, including apps that aren't running.
- [ ] Dragging a row's slider for an app that owns a display changes that display live; for another app it only saves.
- [ ] Remove takes the row away, and the app then follows the default level.
- [ ] An uninstalled app (or a deleted executable) is greyed out.
