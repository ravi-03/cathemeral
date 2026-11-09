# 08: Full popover and status icon

**What to build:** The rest of the popover and menu bar behaviour. Below the display cards, an "other open windows" list shows each running app with on-screen windows, with its window count, a compact slider and its level ("Default" in grey if it has no app setting). A slider updates the screen live whenever its app owns a display, throttled to 30 Hz with no ramp. Otherwise it only saves the level. The list refreshes on open and every 2 s while open, and never polls while closed. The header has the master on/off switch. The footer has "Launch at login" and Quit. The status icon shows its states: sun outline (nothing dimmed), half-filled sun (a display dimmed), sun with a slash (disabled). Right-clicking the icon opens a quick menu: Enable/Disable, Settings, Quit.

**Blocked by:** 04 (Saved app settings and default level), 07 (Multiple displays and display changes)

**Status:** ready-for-agent

- [ ] The list shows every other app with open windows, with correct window counts.
- [ ] Dragging the slider of an app that owns a display changes that display live. For any other app, it only saves the value, which applies the next time the app owns a display.
- [ ] The list refreshes while the popover is open, and no window polling happens while it's closed.
- [ ] The master switch turns all dimming off (every display 100%) and back on.
- [ ] The icon reflects the nothing-dimmed, dimmed and disabled states.
- [ ] The right-click menu works.
- [ ] "Launch at login" registers and unregisters the login item.
