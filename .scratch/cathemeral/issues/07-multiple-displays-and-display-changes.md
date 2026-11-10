# 07: Multiple displays and display changes

**What to build:** Cathemeral works with every connected display. Activation assigns ownership to the display holding the app's key window, and each display keeps its own owner. The popover shows one card per display, named ("Built-in" / the monitor's name), with its owner, level and slider, or "Not dimmed" when unowned. After a display is added, removed or reconfigured, or after sleep and wake (debounced 500 ms), originals are re-captured for every online display, removed displays are dropped, and targets are re-applied without a ramp. Gamma is restored while the screen is locked or another user is active, and re-applied on return.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-human

- [ ] With two displays, Notion at 40% on the external and Safari at 100% on the built-in: clicking into Safari leaves the external display at 40%.
- [ ] The popover shows one card per display, with the right owner and level, and "Not dimmed" for an unowned display.
- [ ] Dragging a slider on a display's card changes that display live.
- [ ] Plugging in or unplugging a monitor or dock leaves every display at the right level within about 1 s, with no stuck-dark display.
- [ ] After sleep and wake, levels are back as before.
- [ ] Locking the screen shows the login window undimmed. Unlocking restores the levels.
- [x] DimmingEngine tests cover independent per-display owners, and re-applying after a display change.

## Comments

**2026-11-10 (agent):** Implemented. This Mac has only the built-in display, so the hand checks above need an external monitor or dock, a sleep and wake, and a screen lock.

- `DimmingEngine` keeps one owner per display (already true), and gains `displays`, `displaysChanged(to:)` and `setSuspended(_:)`. A display change restores the backend, drops owners of removed displays and re-applies every owned display without a ramp. `GammaController` re-captures each original on its next write, after the restore, so the dimmed curve is never captured as the original. While suspended (locked, another user active, or asleep), every display shows its original curve and nothing is written. Ownership and settings still change. On return each owned display fades back over the 150 ms switch ramp, because nothing reset the gamma and a jump would break the no-flash rule.
- `DisplayMonitor` (BrightnessPlatform) reports screen-parameter changes, screen wake and system wake once 500 ms pass with no further notification. It suspends straight away on sleep, `com.apple.screenIsLocked` and session resign. Waking ends the sleep suspension only together with the settled display change, and a wake while locked stays suspended until unlock. A sleep that starts while a wake is still settling stays asleep.
- The popover shows one card per active display (`CGGetActiveDisplayList`, so asleep displays and extra members of a mirrored set get no card). Each card is named "Built-in" or the monitor's `NSScreen.localizedName`.
- `Tools/e2e.sh` now also checks a display change (re-applied, and a second change doesn't dim twice) and suspend and return, through new harness commands `displays-changed`, `suspend` and `unsuspend`. All steps pass.
- Left open:
  - After a monitor is unplugged, a window macOS moves to another display doesn't change that display's owner until the next activation, or until FrontWindowTracker (ticket 06) sees it. Likewise, a newly plugged-in display is "Not dimmed" until an app is brought forward there.
  - Every settled display change restores all displays before re-applying, as the PRD prescribes. A display macOS didn't reset may show a frame or two at 100%. Check for this by hand when plugging in a monitor.
  - A sleep that is vetoed (no wake follows) leaves dimming suspended until the next wake or display change.

