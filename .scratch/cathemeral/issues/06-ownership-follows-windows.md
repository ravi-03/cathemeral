# 06: Ownership follows windows

**What to build:** A display's ownership follows what's actually visible. Hide and quit hand the display over immediately (from the hide and terminate notifications). Minimising or closing the owner's last window, dragging it to another display, or switching Spaces hands it over within about 1 s, through FrontWindowTracker polling the on-screen window list. On handover the display passes to its topmost visible app, or shows 100% if no app is visible (unowned). Each window counts for the display it overlaps most. The tracker runs only while Cathemeral is on and some app setting or the default level is below 100%.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-human

- [ ] Hiding a dimmed owner (Cmd-H) gives the display to the app now on top, at that app's level, immediately.
- [ ] Quitting the owner does the same.
- [ ] Minimising or closing the owner's last window hands the display over within about 1 s.
- [ ] Swiping to an empty desktop Space shows that display at 100%. Swiping to a Space with another app gives that app the display.
- [ ] With nothing set below 100%, the tracker isn't running.
- [x] DimmingEngine tests cover handover after hide, quit, minimise and Space switch: the topmost visible app takes over, an empty display is unowned at 100%, ignored apps are skipped, and focus moving to another display doesn't change ownership.

## Comments

**2026-11-10 (agent):** Implemented. The hide step in `Tools/e2e.sh` passes on the real screen. The other boxes need checking by hand in the app.

- `DimmingEngine.visibleAppsChanged(_:)` takes the apps visible on each display, topmost first. An owner with no visible window on its display loses it. Each display without an owner passes to its topmost visible app that isn't ignored, or stays unowned at 100%. An owner still visible beneath another app keeps its display, and focus elsewhere changes nothing. A handover to an app at the same level writes nothing.
- `appLeft(_:visibleApps:)` handles hide and quit the same way, leaving out the app that left. If that app was mid-switch, any display dimmed early for it goes back to its owner's level.
- No flash:
  - During a switch, a handover never brightens a display dimmed early; `appActivated` sets it right.
  - `ActivationMonitor` reports a hide or quit only once the app's windows are off screen (polled every 4 ms, at most 250 ms), so the display never brightens while the old window still shows.
- `FrontWindowTracker` reports `Displays.visibleApps()` every second, even when unchanged, so an app activated with no windows loses its display within a second. Hidden and quitting apps are left out because their windows can stay listed for a moment. Each window counts for the display it overlaps most.
- The tracker runs only while `needsWindowTracking`: some app setting or the default level is below 100%, and the engine isn't suspended (locked or asleep). The app re-checks this through observation. Ticket 08 should also require the master switch to be on.
- This also closes ticket 07's open items. A window moved by an unplug, or a newly plugged-in display, now gets its owner within a second.

