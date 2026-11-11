# Gamma tables on macOS

These facts were measured by the ticket 01 spike on an M1 with only the built-in display. They were measured on macOS 26.3 and confirmed unchanged on macOS 27.2. The evidence is in `.scratch/cathemeral/issues/01-spike-automated-platform-checks.md` (Comments section), and the code and recorded run are in `spike/` on the `prototype/spike` branch. Apple doesn't document any of this. If macOS behaves differently, rerun `spike/run-all.sh` on that branch.

## The model

- **One table per display.** It is applied to the final composited picture, so it affects every app on that display equally. No app can have a table of its own. That's why ADR 0001 dims whole displays.
- **Reads are global.** `CGGetDisplayTransferByTable` returns the same table in every process, including processes that never wrote gamma.
- **The last write wins.** Writes from different processes replace each other; they don't stack.
- **WindowServer remembers which processes have written to the table.** When any of them exits, for any reason including SIGKILL, the display resets to its ColorSync curve, even if a different process wrote last. This took 65–67 ms after a SIGKILL. A process that never wrote gamma doesn't trigger the reset when it exits.
- **`CGDisplayRestoreColorSyncSettings` only undoes the caller's own writes.** Called from a process that never wrote, it does nothing.

## What follows for Cathemeral

- **The screen can't be left dim by a crash.** When the app dies, macOS restores the screen itself.
- **Restoring a hung app's gamma from outside needs a restorer.** The restorer is a one-shot process that writes each display's current table back unchanged and exits. Its exit triggers the reset. The watchdog (`App/GammaWatchdog`) runs it as `GammaWatchdog restore` on a heartbeat timeout, waits 200 ms for the reset to land, then signals the app, which fades its levels back in (`SafetyNet`, `DimmingEngine.restoredFromOutside`). The watchdog itself never writes gamma, because then its own exit would reset the app's dimming.
- **Our dimming is silently wiped when any other gamma writer exits** (f.lux, Lunar, a calibration tool, the restorer). Nothing notifies the app, so it reads its tables back (next section).

## Reading tables back

Ticket 10 found that each rule here, taken any other way, either fights another app or pauses for nothing. `TableWatch` (BrightnessCore) implements them, `GammaController` reads the tables, and `Tools/e2e.sh paused` checks them on the real screen.

- **A read straight after a write returns that write.** So a read-back after our own write proves only that the write took. It's taken after a fade's last frame or a single write (a read can stall during an app switch, see Timing), and its only uses are spotting an unsupported display (three writes that leave the original on screen before any write has taken) and a reset landing just after the write.
- **Only the 1 Hz tick counts toward pausing.** Another app's table on three ticks in a row pauses the display. Only a tick where our table survived starts the count again. If our own write's read-back did, every app switch would write over f.lux, read back as ours, and the two would fight for as long as the user kept switching.
- **A reset is re-applied straight away and never counts as another app's table.** A reset is a table equal to the captured original, or, after a Resume, the curve from before it: Resume captures the other app's colours as the original, and when that app quits the display resets to the earlier curve. That earlier curve is then captured as the original.
- **A reset on three ticks in a row pauses too.** Something keeps writing the original back, and re-applying would flash dim and bright every second.
- **A display at 100% has nothing of ours on screen**, so another curve there is no fight. It's captured silently as the original, so the next dim scales what's on screen rather than writing over it.
- **Writes can block.** One `CGSetDisplayTransferByTable` call takes about 0.06 ms back-to-back, but often 5–15 ms and up to about 30 ms when writes are spaced out or WindowServer is busy with an app switch. Keep writes off the main actor.

## Timing

Measured with `Tools/switch-timing` during tickets 04 and 05, on the built-in 60 Hz display of a MacBook Air, macOS 27.2. Each fact cost a debugging round to find.

- **An activation is announced before its window comes forward.** `NSWorkspace.didActivateApplicationNotification` arrives 20–70 ms before the app's window is topmost in the on-screen window list (Notion to iTerm2: 52–71 ms; iTerm2 to Notion: 18–38 ms). A gamma write made on the notification shows the old app's window at the new level for those frames. This is why the engine dims on the announcement and brightens only once the window is in front.
- **A write shows from the first refresh after the call returns.** Only the last table written before a refresh is ever seen, so two writes inside one refresh lose the first, and a write that returns after its refresh shows one refresh late.
- **The first display link is slow to create.** The first `NSScreen.displayLink` in a process took 81 ms, blocking the main thread. After that, the link reports a steady refresh (16.67 ms here), and a paused link's first tick can be up to two refreshes away.
- **Gamma reads stall too.** While WindowServer is busy with an app switch, `CGGetDisplayTransferByTable` from another process can block for about 50 ms, so a probe can miss frames. Check the time between samples before calling a big step a jump.
- **Fast `open -b` bursts confuse the frontmost app.** Opening two apps 60 ms apart can leave `NSWorkspace.frontmostApplication` naming one app while the other's window is on top. Read the window list, not the frontmost app, when a check needs to know what is showing.

## Checking it on this Mac

`Tools/e2e.sh` checks dimming on the real built-in display, and `Tools` also has `peek`, which reads each display's gamma without writing it. See `Tools/README.md`.

## Not yet verified

- Whether one writer's exit resets every display or only the ones it wrote to. Needs an external monitor (ticket 02).
- Whether a writer's own restore call also resets a table that another process wrote after it.
- Whether Night Shift and True Tone go through this table (ticket 02).
