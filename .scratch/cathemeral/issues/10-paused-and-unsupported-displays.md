# 10: Paused and unsupported displays

**What to build:** Cathemeral never fights another app over a display's colours. After each gamma write, the controller reads the table back. Three mismatches in a row pause that display only: no more writes to it, while other displays carry on. The paused display's card says "Another app is controlling this display's colours" and shows a Resume button, and the status icon shows a dot. Resume re-captures the display's current curve as its original and re-applies the owner's level. Another mismatch pauses it again, and nothing resumes automatically. When any other gamma-writing process exits, WindowServer silently resets every display (ticket 01). So while a display is dimmed, the controller also reads it back on the 1 Hz window tick. A table equal to the captured original is a reset: re-apply silently, with no mismatch counted. A display where gamma writes never take (some HDR/EDR, Sidecar or AirPlay displays) is marked "unsupported" on its card.

**Blocked by:** 07 (Multiple displays and display changes)

**Status:** ready-for-human

- [x] With f.lux (or any app that writes gamma) running, the affected display pauses within three writes, and its card shows the message and Resume.
- [ ] Other displays keep dimming while one is paused.
- [x] Resume dims on top of the other app's colours. If the other app rewrites, the display pauses again.
- [ ] The status icon shows the dot while any display is paused.
- [x] Quitting another gamma-writing app while a display is dimmed re-applies the dimming within about 1 s, without pausing the display.
- [ ] A display where gamma doesn't apply is shown as "unsupported".
- [x] DimmingEngine tests confirm a paused display gets no target, and Resume restores its target.

## Comments

### 2026-11-11: from the ticket 09 retro (agent)

- The heartbeat interval (`SafetyNet.heartbeatInterval`, 250 ms) and the watchdog's timeout (`heartbeatTimeout` in `App/GammaWatchdog/main.swift`, 1500 ms) only work together but live in two files. While touching the safety net here, have `SafetyNet` pass `--timeout-ms` when it launches the watchdog, so one file owns both numbers.
- Ticket 09 left two gaps for this ticket's 1 Hz table re-check to cover: a false watchdog restore just after wake, and a re-apply wiped by a reset that lands after it. In both cases the table equals the captured original, which this ticket re-applies silently.

### 2026-11-11: implemented (agent)

- `TableWatch` (BrightnessCore) decides what each read-back means. `GammaController` reads back after a fade's last frame or a single write, and on every window tick. Only the last frame is read back, because a read can stall about 50 ms during a switch. A mismatch is counted on ticks only, and only a tick where our table survived resets the count. Our own write always reads back as ours, so if a write could reset the count, switching apps often would keep the two apps fighting. In practice it pauses on three ticks, about 2–3 s, not "three writes".
- These behaviours weren't spelled out in the ticket, but are needed to keep its promises. A table reset on three ticks in a row also pauses, since something keeps re-writing the original and re-applying would flash every second. After Resume, a reset to the curve from before Resume is re-captured and re-applied, so f.lux quitting after a Resume doesn't pause. A display at 100% showing another curve has it re-captured silently, with no write, so the next dim scales what's on screen. An unsupported display is tried again on the next display change.
- `scripts/check` passes (104 tests). `Tools/e2e.sh` passes, including the new paused-displays section with `Tools/Sources/other-app` standing in for f.lux.
- Done from the ticket 09 retro: `SafetyNet` passes `--timeout-ms` and owns both numbers.

Left for a human (needs hardware or eyes):
- [ ] Real f.lux, not the stand-in.
- [ ] Other displays keep dimming while one is paused (needs an external monitor; covered by an engine test).
- [ ] The status-icon dot, and the paused and unsupported cards, look right.
- [ ] An unsupported display (Sidecar, AirPlay or HDR). Only tables that can't be read, and writes whose read-back shows the original, are detected. A display that stores the table but doesn't show it can't be detected.

Open points:
- **Timing (settled).** A reset is re-applied within one tick (1 s) plus a queued read and write (up to about 80 ms), so about 1.1 s in the worst case. "About 1 s" is a target, not a firm bound (decided 2026-11-11, now in CODING_STANDARDS.md), so this is accepted.
- If the app recovers from a hang within the watchdog's 200 ms settle time, a tick can re-apply the restorer's reset with a jump before SIGUSR1 arrives. CODING_STANDARDS.md wants a fade after our own restore.
- A write already in progress when a display pauses still lands, once.
- Whether Night Shift writes this table is still open (ticket 02). If it does, dimmed displays would pause every evening.

