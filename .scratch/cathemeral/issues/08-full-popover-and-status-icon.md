# 08: Full popover and status icon

**What to build:** The rest of the popover and menu bar behaviour. Below the display cards, an "other open windows" list shows each running app with on-screen windows, with its window count, a compact slider and its level ("Default" in grey if it has no app setting). A slider updates the screen live whenever its app owns a display, throttled to 30 Hz with no ramp. Otherwise it only saves the level. The list refreshes on open and every 2 s while open, and never polls while closed. The header has the master on/off switch. The footer has "Launch at login" and Quit. The status icon shows its states: sun outline (nothing dimmed), half-filled sun (a display dimmed), sun with a slash (disabled). Right-clicking the icon opens a quick menu: Enable/Disable, Settings, Quit.

**Blocked by:** 04 (Saved app settings and default level), 07 (Multiple displays and display changes)

**Status:** ready-for-human

- [ ] The list shows every other app with open windows, with correct window counts.
- [ ] Dragging the slider of an app that owns a display changes that display live. For any other app, it only saves the value, which applies the next time the app owns a display.
- [ ] The list refreshes while the popover is open, and no window polling happens while it's closed.
- [ ] The master switch turns all dimming off (every display 100%) and back on.
- [ ] The icon reflects the nothing-dimmed, dimmed and disabled states.
- [ ] The right-click menu works.
- [ ] "Launch at login" registers and unregisters the login item.

## Comments

### 2026-11-11: implemented (agent)

- The menu bar icon and popover moved from SwiftUI's `MenuBarExtra` to an AppKit `StatusItemController` (`NSStatusItem` + `NSPopover`). `MenuBarExtra` can't tell a right-click from a click, and the popover's open and close are needed to start and stop window polling.
- **Master switch** (`DimmingEngine.setEnabled`). Saved in the settings file, now schema version 2; a version 1 file loads with dimming on. Turning it off fades every dimmed display to 100% over the switch ramp through the `Fader`, rather than restoring, which would jump (CODING_STANDARDS.md, No flash). Turning it back on fades every owned display back in. While it's off, windows aren't tracked, so a display whose owner left meanwhile is handed over by the first window tick after turning back on, about 1 s after a possibly stale fade-in.
- **Slider throttle.** Every settings change (any slider, "Use default") reaches the screen at most 30 times a second, with no ramp; the last value always lands, at most 33 ms late. Mid-switch, a delayed settings write never brightens a display dimmed early (the same rule as `visibleAppsChanged`).
- **Other open windows.** `WindowInventory` (BrightnessPlatform) counts on-screen layer-0 windows per app, on popover open and every 2 s until it closes. `DimmingEngine.otherOpenApps` leaves out the owner of each dimming display and ignored apps, sorted by name. The owner of a paused display stays in the list, since its card doesn't show it.
- **Icon.** `DimmingEngine.dimmingState`: `.off`, `.nothingDimmed` (sun outline), `.dimmed` (`sun.lefthalf.filled`). SF Symbols has no slashed sun, so the slash for `.off` is drawn. The paused dot still shows on top of any state.
- The right-click menu's Settings… opens a small Settings window (default level and launch at login). Ticket 11 replaces its contents with the Apps list and recovery steps.
- `scripts/check` passes (117 tests). Engine tests cover the switch, its save and migration, the throttle, the mid-switch guard, the list filter and the icon state.
- `Tools/e2e.sh` hasn't run: it refused because a Debug Cathemeral from an earlier build was running.

Left for a human:
- [ ] Run `Tools/e2e.sh` with Cathemeral quit.
- [ ] The list shows every other app with open windows, with correct window counts, and refreshes while open.
- [ ] Dragging a card's slider changes the display live; a list slider only saves, and applies the next time that app owns a display.
- [ ] The master switch fades every display to 100% and back.
- [ ] The three icon states (and the slash drawing) look right in light and dark menu bars.
- [ ] Right-click and Control-click open the menu; Enable/Disable, Settings… and Quit work.
- [ ] Launch at login registers and unregisters (check System Settings ▸ General ▸ Login Items; may need a signed build).

