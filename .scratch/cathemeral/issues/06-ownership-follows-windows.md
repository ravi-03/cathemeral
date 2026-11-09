# 06: Ownership follows windows

**What to build:** A display's ownership follows what's actually visible. Hide and quit hand the display over immediately (from the hide and terminate notifications). Minimising or closing the owner's last window, dragging it to another display, or switching Spaces hands it over within about 1 s, through FrontWindowTracker polling the on-screen window list. On handover the display passes to its topmost visible app, or shows 100% if no app is visible (unowned). Each window counts for the display it overlaps most. The tracker runs only while Cathemeral is on and some app setting or the default level is below 100%.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-agent

- [ ] Hiding a dimmed owner (Cmd-H) gives the display to the app now on top, at that app's level, immediately.
- [ ] Quitting the owner does the same.
- [ ] Minimising or closing the owner's last window hands the display over within about 1 s.
- [ ] Swiping to an empty desktop Space shows that display at 100%. Swiping to a Space with another app gives that app the display.
- [ ] With nothing set below 100%, the tracker isn't running.
- [ ] DimmingEngine tests cover handover after hide, quit, minimise and Space switch: the topmost visible app takes over, an empty display is unowned at 100%, ignored apps are skipped, and focus moving to another display doesn't change ownership.
