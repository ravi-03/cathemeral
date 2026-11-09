# 01: Spike: automated platform checks

**What to build:** A throwaway prototype that answers the open questions the build depends on, using checks an agent can run and verify by itself. It dims a display through the gamma table and reads the table back to confirm each result, so no one has to watch the screen. Keep the code on a `prototype/spike` branch as a primary source. Record every answer in this ticket under `## Comments`, and update the PRD's "Open questions for the spike" if any answer changes the design. If the agent's shell can't reach WindowServer, leave a one-command script for the user to run in Terminal and record its output.

See the PRD (Implementation Decisions → Open questions for the spike) and ADR 0001.

**Blocked by:** None (can start immediately)

**Status:** ready-for-agent

- [x] Answered: can a separate helper process reset gamma set by another process by restoring ColorSync settings? (Yes/no, with the read-back evidence.)
- [x] Answered: does macOS restore gamma by itself when the process that set it is killed with SIGKILL? (Checked from a fresh process.)
- [x] Measured: a pipe-heartbeat watchdog restores gamma within 2 s of the app being frozen with SIGSTOP.
- [x] Measured: time for one on-screen window list call (median and p95 over at least 100 calls), with the number of windows open noted.
- [x] Measured: software latency from the activation notification to the first gamma write (median and p95 over at least 30 app switches).
- [x] A probe script exists that prints each display's current gamma state, for the manual checks in ticket 02.
- [x] Every test restores the original gamma at the end, and the screen is left as it was found.
- [x] If an answer breaks an assumption (such as the watchdog being unable to restore), the consequence for the safety-net design is written in the ticket.

## Comments

### 2026-11-09: spike results (agent)

Code and raw output: branch `prototype/spike`, folder `spike/` (`spike/results.txt` is the recorded run; `spike/run-all.sh` repeats it). Machine: Apple M1, macOS 26.3 (25D125), built-in display only (1440x900, 1024-entry tables). The agent's shell could reach WindowServer, so no hand-run script was needed. Every check reads the gamma table back from a separate process that never wrote gamma, and ends by comparing the table with the baseline fingerprint. Every run left the screen as found.

**Q1. Can a separate helper reset another process's gamma with `CGDisplayRestoreColorSyncSettings`? No.** With a holder process dimmed to 0.6, a third process called the restore. A fresh process still read peak 0.6000 straight after and 1 s later, with the holder alive and not re-writing. The restore only undoes the calling process's own gamma.

Follow-up checks (`q1b`) showed how gamma ownership actually works:
- **The last write wins across processes.** Another process writing the original table (or an identity formula) over the holder made the display read 1.0. The holder's next write took it back to 0.6.
- **When any process that wrote gamma exits, WindowServer resets every display to ColorSync defaults, even if a different process wrote last.** The writer exited while the holder's 0.6 was the latest table, and the display went to 1.0 with the holder still alive. A process that only called the restore and never wrote doesn't trigger this.

**Q2. Does macOS restore gamma when the setting process is SIGKILLed? Yes.** A non-writing process saw the display undimmed 69 ms after the SIGKILL, and a new fresh process read peak 1.0000.

**Q3. Does a pipe-heartbeat watchdog restore within 2 s of SIGSTOP? Not as designed. Yes with two changes.**
- The PRD design, where the watchdog calls `CGDisplayRestoreColorSyncSettings` on a heartbeat timeout, **never restored** (2/2 trials). The timeout fired and the call returned, but the frozen app's gamma stayed.
- **The fix:** on a timeout, the watchdog spawns a one-shot **restorer** process. The restorer writes each display's current table back unchanged (no visible change) and exits, and its exit makes WindowServer reset every display (Q1 follow-up). This needs no copy of the original curve, so it can't go stale. It worked every time.
- With the PRD's **2 s timeout**: SIGSTOP to undimmed took median 1995 ms, worst 2059 ms (10 trials). That's over the target, because restore time is the timeout plus up to one heartbeat of phase, plus about 65 ms to spawn the restorer.
- With a **1.5 s timeout**: median 1285–1356 ms, worst 1518–1562 ms across 40 trials in three runs. All within 2 s.
- **Recovery:** after SIGCONT, the app got the watchdog's SIGUSR1 and re-applied its level in 40/40 trials. Its write wins because the last write wins.
- **App death** with the watchdog running: the watchdog saw end-of-file and exited, and the screen was undimmed. macOS does this restore anyway (Q2), so the end-of-file path is a backup, not essential.

**Q4. Cost of one on-screen window list call** (`CGWindowListCopyWindowInfo(.optionOnScreenOnly, .excludeDesktopElements)`, 300 calls). "+ assignment" adds the layer-0 filter and assigning each window to the display it overlaps most:

| Windows on screen (layer 0) | Call median / p95 | Call + assignment median / p95 |
|---|---|---|
| 21 (8) | 0.35 / 1.1 ms | 0.37 / 1.1 ms |
| 71 (58), 50 extra windows opened by the spike | 0.83 / 3.3 ms | 0.86 / 3.4 ms |
| 120 (107), 100 extra windows | 1.34 / 6.3 ms | 1.47 / 6.6 ms |

At 1 Hz that's about 0.1% of one core with ~50 windows. There are rare outliers of 20–70 ms (the max of 300 calls).

**Q5. Activation notification to first gamma write** (40 switches between iTerm2 and Finder, with `NSRunningApplication.activate`): notification to write returned had median 5.3 ms, p95 12.7 ms, max 17.0 ms. Switch request to notification delivered had median 6.7 ms, p95 13.9 ms. Two earlier clean runs agreed (medians 6.0–6.2 ms, p95 15.8–17.6 ms). In one run on a busier machine, with Chrome in front, `activate()` was refused (cooperative activation, macOS 14+) and the harness fell back to `open -b`. Notification to write then had p95 31 ms and max 85 ms. That's still under 100 ms but with less margin. `q5b` showed the write call itself costs 0.04–0.08 ms back-to-back, but up to about 9 ms for the first write after idle. That's not locked to vsync, but it argues for keeping writes off the main actor, as planned. Glass-to-glass latency is for ticket 02's 240 fps video.

**Probe for ticket 02:** `git switch prototype/spike && spike/probe.sh` prints each display's gamma state (entries, peak, mid-point, fingerprint) and prints a new block whenever any table changes. Use `spike/probe.sh --once` for a single print, and `spike/.build/release/spike restorer` if the screen is ever stuck dim.

### Consequences for the design

1. **Watchdog hang restore (ticket 09).** Replace "the watchdog restores ColorSync settings" with "the watchdog spawns a one-shot restorer that writes each display's current table back unchanged and exits". Use a 1.5 s heartbeat timeout instead of 2 s, so a main-thread stall under 1 s never triggers a restore, and a hang is always restored within 2 s. The watchdog itself must never write gamma: if it did, its own exit would wipe the app's dimming.
2. **Crash restore is free.** macOS restores within about 70 ms when the app dies for any reason, including SIGKILL. The watchdog's end-of-file path is a backup only.
3. **New risk: our dimming is silently reset when any other gamma writer exits** (f.lux, Lunar, a calibration tool, or our own restorer). Nothing notifies us. Readback happens only after our own writes, so with no app switch the display sits at 100% until the next one. The table is then equal to the captured original, which is not a foreign table, so it must not count as a pause mismatch. Proposed fix: on the existing 1 Hz tick, read each dimmed display's table back (one read per display; its cost wasn't measured). If it equals what we wrote, do nothing. If it equals the captured original, re-apply silently. Anything else counts as a mismatch toward pausing (ticket 10).
4. **The restorer resets all displays, as far as this one-display Mac can show.** Confirm with an external monitor in ticket 02.
5. **Latency and window-list cost fit the budgets.** Activation to first write is about 5 ms median and under 20 ms at p95, leaving most of the 100 ms for the display. The 1 Hz window list costs about 0.1% of a core. No design change, but consider calling the window list off the main actor because of its rare 20–70 ms outliers.
6. **Toolchain (ticket 03).** This Mac has only the Command Line Tools, so `xcodebuild` isn't available. Ticket 03's app target needs Xcode installed, or a SwiftPM executable wrapped into an `.app` bundle by a script.
