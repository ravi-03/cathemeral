# 07: Multiple displays and display changes

**What to build:** Cathemeral works with every connected display. Activation assigns ownership to the display holding the app's key window, and each display keeps its own owner. The popover shows one card per display, named ("Built-in" / the monitor's name), with its owner, level and slider, or "Not dimmed" when unowned. After a display is added, removed or reconfigured, or after sleep and wake (debounced 500 ms), originals are re-captured for every online display, removed displays are dropped, and targets are re-applied without a ramp. Gamma is restored while the screen is locked or another user is active, and re-applied on return.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-agent

- [ ] With two displays, Notion at 40% on the external and Safari at 100% on the built-in: clicking into Safari leaves the external display at 40%.
- [ ] The popover shows one card per display, with the right owner and level, and "Not dimmed" for an unowned display.
- [ ] Dragging a slider on a display's card changes that display live.
- [ ] Plugging in or unplugging a monitor or dock leaves every display at the right level within about 1 s, with no stuck-dark display.
- [ ] After sleep and wake, levels are back as before.
- [ ] Locking the screen shows the login window undimmed. Unlocking restores the levels.
- [ ] DimmingEngine tests cover independent per-display owners, and re-applying after a display change.
