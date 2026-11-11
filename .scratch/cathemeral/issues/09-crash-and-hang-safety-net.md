# 09: Crash and hang safety net

**What to build:** The screen is never left dim, whatever happens to the app. Termination signals restore gamma before exiting. If the app dies, macOS resets its gamma itself (65 ms, measured in ticket 01). A small watchdog helper, embedded in the app bundle and launched at startup, holds a pipe to the app. The app writes a heartbeat byte every 500 ms from the main run loop. The watchdog waits with a 1.5 s timeout. End-of-file means the app died: macOS has already restored, so the watchdog exits. A timeout means the app is hung: the watchdog spawns a one-shot restorer process that writes each display's current table back unchanged and exits, and that exit makes WindowServer reset every display. The watchdog then signals back. If the app recovers, it re-applies its targets with a ramp. The watchdog never writes gamma itself, so its own death leaves the screen as it is, but it leaves the app without hang protection. The app notices when the watchdog dies (the heartbeat write fails, or a process-exit notification fires) and relaunches it. App Nap is disabled for the heartbeat through a user-initiated activity.

Updated from ticket 01's answers: calling `CGDisplayRestoreColorSyncSettings` from the watchdog does nothing to the app's gamma, and a 2 s timeout plus the restorer's spawn time overshoots 2 s. Working reference code: `hold`, `watchdog` and `restorer` in `spike/Sources/spike/main.swift` on `prototype/spike`.

**Already built in ticket 03:** SIGTERM, SIGINT and SIGHUP restore gamma through dispatch signal sources in `AppDelegate.restoreOnTerminationSignals()` (`App/Cathemeral/CathemeralApp.swift`), because `CODING_STANDARDS.md` requires a restore on every exit path. For the first box, verify that rather than rebuild it. `Tools/e2e.sh` and `peek` can read the result back.

**Blocked by:** 01 (Spike: automated platform checks), 03 (Tracer bullet: frontmost app dims its display)

**Status:** done

- [x] SIGTERM, SIGINT and SIGHUP each restore the original gamma before the app exits.
- [x] `kill -9` on a dimmed app restores the original gamma.
- [x] `kill -STOP` on a dimmed app restores the original gamma within 2 s. `kill -CONT` brings the dimming back with a ramp.
- [x] A main-thread pause shorter than 1 s never triggers a restore.
- [x] The watchdog uses effectively no CPU while idle.
- [x] `kill -9` on the watchdog leaves the dimming unchanged, and a new watchdog is running within about 1 s. A later `kill -STOP` on the app is still restored within 2 s.

## Comments

### 2026-11-11: implemented (agent)

- **Watchdog and restorer:** `App/GammaWatchdog` (an Xcode tool target, copied into `Cathemeral.app/Contents/MacOS`). `GammaWatchdog <app-pid>` polls its heartbeat pipe with a 1.5 s timeout; `GammaWatchdog restore` is the one-shot restorer, the only gamma write outside `GammaController` (allowed in `scripts/check`). After the restorer exits, the watchdog waits 200 ms for WindowServer's reset to land before sending SIGUSR1, so a re-apply from an app that has just recovered isn't wiped by the reset.
- **App side:** `SafetyNet` (BrightnessPlatform) now owns the termination signals (moved from `AppDelegate`, same behaviour), launches the watchdog, beats every 500 ms from a main-run-loop timer in common modes, holds a `userInitiatedAllowingIdleSystemSleep` activity against App Nap (so it doesn't stop idle sleep, unlike the spike's activity), and turns SIGUSR1 into `DimmingEngine.restoredFromOutside()`, which restores the backend and fades every owned display back over `switchRamp` (unit-tested). A failed heartbeat write (EPIPE, or EAGAIN from a full pipe because the watchdog stopped reading) or the watchdog's exit replaces it. The write end is non-blocking and has `F_SETNOSIGPIPE` set, so a dead watchdog can't kill or block the app. A watchdog that dies within 1 s of launch is relaunched after 1 s.
- **Evidence:** `Tools/e2e.sh` now runs every box against the real `SafetyNet` and watchdog through the harness. Run on 2026-11-11, all ok: SIGTERM/SIGINT/SIGHUP restore; `kill -9` restores and the watchdog exits with the app; four 0.95 s pauses at different heartbeat phases didn't trigger a restore; idle watchdog CPU was 0.01 s over 5 s; `kill -STOP` restored in 1440 ms, and `kill -CONT` faded back through the watchdog's signal; after `kill -9` on the watchdog the dimming stayed, a new watchdog was running within 1 s, and `kill -STOP` was then restored in 1094 ms. The real app bundle was also checked by hand: it launches its embedded watchdog and replaces it after `kill -9`.
- **Changed from the ticket: heartbeat every 250 ms, not 500 ms.** Both reviewers pointed out that at 500 ms, a pause just under 1 s that starts just before a beat leaves a gap of about 1.49 s, right at the 1.5 s timeout. At 250 ms the gap is at most 1.25 s, and the restore time is unchanged. Rerun of `Tools/e2e.sh` after the change: all ok, four 0.95 s stalls at different phases, idle watchdog CPU 0.01 s over 5 s, `kill -STOP` restored in 1301 ms and 1362 ms (restorer 134–138 ms).
- **Known gaps (outside the boxes):** a *stopped* watchdog (`kill -STOP` on the watchdog itself) is only noticed when the heartbeat pipe fills, which takes hours, so there is no hang protection until then. If the restorer fails to launch, that hang isn't retried. After wake, a heartbeat timeout that fires just after the engine unsuspends would show the original curve and then fade back. This is harmless but visible, and it hasn't been seen.
