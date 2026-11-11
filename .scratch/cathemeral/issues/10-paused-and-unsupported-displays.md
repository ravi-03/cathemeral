# 10: Paused and unsupported displays

**What to build:** Cathemeral never fights another app over a display's colours. After each gamma write, the controller reads the table back. Three mismatches in a row pause that display only: no more writes to it, while other displays carry on. The paused display's card says "Another app is controlling this display's colours" and shows a Resume button, and the status icon shows a dot. Resume re-captures the display's current curve as its original and re-applies the owner's level. Another mismatch pauses it again, and nothing resumes automatically. When any other gamma-writing process exits, WindowServer silently resets every display (ticket 01). So while a display is dimmed, the controller also reads it back on the 1 Hz window tick. A table equal to the captured original is a reset: re-apply silently, with no mismatch counted. A display where gamma writes never take (some HDR/EDR, Sidecar or AirPlay displays) is marked "unsupported" on its card.

**Blocked by:** 07 (Multiple displays and display changes)

**Status:** ready-for-agent

- [ ] With f.lux (or any app that writes gamma) running, the affected display pauses within three writes, and its card shows the message and Resume.
- [ ] Other displays keep dimming while one is paused.
- [ ] Resume dims on top of the other app's colours. If the other app rewrites, the display pauses again.
- [ ] The status icon shows the dot while any display is paused.
- [ ] Quitting another gamma-writing app while a display is dimmed re-applies the dimming within about 1 s, without pausing the display.
- [ ] A display where gamma doesn't apply is shown as "unsupported".
- [ ] DimmingEngine tests confirm a paused display gets no target, and Resume restores its target.

## Comments

### 2026-11-11: from the ticket 09 retro (agent)

- The heartbeat interval (`SafetyNet.heartbeatInterval`, 250 ms) and the watchdog's timeout (`heartbeatTimeout` in `App/GammaWatchdog/main.swift`, 1500 ms) only work together but live in two files. While touching the safety net here, have `SafetyNet` pass `--timeout-ms` when it launches the watchdog, so one file owns both numbers.
- Ticket 09 left two gaps for this ticket's 1 Hz table re-check to cover: a false watchdog restore just after wake, and a re-apply wiped by a reset that lands after it. In both cases the table equals the captured original, which this ticket re-applies silently.
