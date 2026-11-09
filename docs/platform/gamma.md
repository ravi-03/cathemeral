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
- **Restoring a hung app's gamma from outside needs a restorer.** The restorer is a one-shot process that writes each display's current table back unchanged and exits. Its exit triggers the reset. The watchdog spawns it on a heartbeat timeout (ticket 09). The watchdog itself never writes gamma, because then its own exit would reset the app's dimming.
- **Our dimming is silently wiped when any other gamma writer exits** (f.lux, Lunar, a calibration tool, the restorer). Nothing notifies the app. While a display is dimmed, re-check its table on the 1 Hz tick. A table equal to the captured original means it was reset: re-apply silently. Any other table counts as a mismatch toward pausing the display (ticket 10).
- **Writes can block.** One `CGSetDisplayTransferByTable` call takes about 0.06 ms back-to-back, but up to about 10 ms when writes are spaced out. Keep writes off the main actor.

## Not yet verified

- Whether one writer's exit resets every display or only the ones it wrote to. Needs an external monitor (ticket 02).
- Whether a writer's own restore call also resets a table that another process wrote after it.
- Whether Night Shift and True Tone go through this table (ticket 02).
