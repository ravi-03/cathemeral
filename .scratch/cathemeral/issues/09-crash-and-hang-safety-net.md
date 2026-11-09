# 09: Crash and hang safety net

**What to build:** The screen is never left dim, whatever happens to the app. Termination signals restore gamma before exiting. A small watchdog helper, embedded in the app bundle and launched at startup, holds a pipe to the app. The app writes a heartbeat byte every 500 ms from the main run loop. The watchdog waits with a 2 s timeout. End-of-file means the app died: the watchdog restores ColorSync settings and exits. A timeout means the app is hung: the watchdog restores and signals back. If the app recovers, it re-applies its targets with a ramp. App Nap is disabled for the heartbeat through a user-initiated activity.

Adjust this design to the spike's answers in ticket 01. If the watchdog can't restore another process's gamma, or macOS already restores on exit, update this ticket first.

**Blocked by:** 01 (Spike: automated platform checks), 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-agent

- [ ] SIGTERM, SIGINT and SIGHUP each restore the original gamma before the app exits.
- [ ] `kill -9` on a dimmed app restores the original gamma.
- [ ] `kill -STOP` on a dimmed app restores the original gamma within 2 s. `kill -CONT` brings the dimming back with a ramp.
- [ ] A pause shorter than 2 s never triggers a restore.
- [ ] The watchdog uses effectively no CPU while idle.
