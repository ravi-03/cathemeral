# 09: Crash and hang safety net

**What to build:** The screen is never left dim, whatever happens to the app. Termination signals restore gamma before exiting. If the app dies, macOS resets its gamma itself (65 ms, measured in ticket 01). A small watchdog helper, embedded in the app bundle and launched at startup, holds a pipe to the app. The app writes a heartbeat byte every 500 ms from the main run loop. The watchdog waits with a 1.5 s timeout. End-of-file means the app died: macOS has already restored, so the watchdog exits. A timeout means the app is hung: the watchdog spawns a one-shot restorer process that writes each display's current table back unchanged and exits, and that exit makes WindowServer reset every display. The watchdog then signals back. If the app recovers, it re-applies its targets with a ramp. The watchdog never writes gamma itself, so its own death leaves the screen as it is, but it leaves the app without hang protection. The app notices when the watchdog dies (the heartbeat write fails, or a process-exit notification fires) and relaunches it. App Nap is disabled for the heartbeat through a user-initiated activity.

Updated from ticket 01's answers: calling `CGDisplayRestoreColorSyncSettings` from the watchdog does nothing to the app's gamma, and a 2 s timeout plus the restorer's spawn time overshoots 2 s. Working reference code: `hold`, `watchdog` and `restorer` in `spike/Sources/spike/main.swift` on `prototype/spike`.

**Already built in ticket 03:** SIGTERM, SIGINT and SIGHUP restore gamma through dispatch signal sources in `AppDelegate.restoreOnTerminationSignals()` (`App/Cathemeral/CathemeralApp.swift`), because `CODING_STANDARDS.md` requires a restore on every exit path. For the first box, verify that rather than rebuild it. `Tools/e2e.sh` and `peek` can read the result back.

**Blocked by:** 01 (Spike: automated platform checks), 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-agent

- [ ] SIGTERM, SIGINT and SIGHUP each restore the original gamma before the app exits.
- [ ] `kill -9` on a dimmed app restores the original gamma.
- [ ] `kill -STOP` on a dimmed app restores the original gamma within 2 s. `kill -CONT` brings the dimming back with a ramp.
- [ ] A main-thread pause shorter than 1 s never triggers a restore.
- [ ] The watchdog uses effectively no CPU while idle.
- [ ] `kill -9` on the watchdog leaves the dimming unchanged, and a new watchdog is running within about 1 s. A later `kill -STOP` on the app is still restored within 2 s.
