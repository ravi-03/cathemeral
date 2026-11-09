# 09: Crash and hang safety net

**What to build:** The screen is never left dim, whatever happens to the app. Termination signals restore gamma before exiting. If the app dies, macOS resets its gamma itself (65 ms, measured in ticket 01). A small watchdog helper, embedded in the app bundle and launched at startup, holds a pipe to the app. The app writes a heartbeat byte every 500 ms from the main run loop. The watchdog waits with a 1.5 s timeout. End-of-file means the app died: macOS has already restored, so the watchdog exits. A timeout means the app is hung: the watchdog spawns a one-shot restorer process that writes each display's current table back unchanged and exits, and that exit makes WindowServer reset every display. The watchdog then signals back. If the app recovers, it re-applies its targets with a ramp. The watchdog never writes gamma itself. App Nap is disabled for the heartbeat through a user-initiated activity.

Updated from ticket 01's answers: calling `CGDisplayRestoreColorSyncSettings` from the watchdog does nothing to the app's gamma, and a 2 s timeout plus the restorer's spawn time overshoots 2 s. Working reference code: `hold`, `watchdog` and `restorer` in `spike/Sources/spike/main.swift` on `prototype/spike`.

**Blocked by:** 01 (Spike: automated platform checks), 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-agent

- [ ] SIGTERM, SIGINT and SIGHUP each restore the original gamma before the app exits.
- [ ] `kill -9` on a dimmed app restores the original gamma.
- [ ] `kill -STOP` on a dimmed app restores the original gamma within 2 s. `kill -CONT` brings the dimming back with a ramp.
- [ ] A main-thread pause shorter than 1 s never triggers a restore.
- [ ] The watchdog uses effectively no CPU while idle.
