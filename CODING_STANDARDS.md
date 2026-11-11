# Coding standards

The code reviewer applies these. Anything a tool can check belongs in the `check` script instead.

## Gamma safety

The screen must never be left dim. See `docs/platform/gamma.md` for how gamma works across processes.

- **Every exit path restores gamma.** Any code that writes gamma must restore it on every way out: normal return, thrown errors, early returns, signal handlers, and failure paths in tests and tools. When a check or tool starts child processes that write gamma, its failure path ends those children. A restore call in the parent can't undo a child's writes. A hang is an exit path too: every wait on a gamma-writing child (a `wait`, a poll, opening a FIFO) is bounded, and the script as a whole has a deadline that ends those children by pid (`Tools/e2e.sh`, `arm_deadline`).
- **The watchdog and any helper that only exists to restore never write gamma**, apart from the restorer's single write-back just before it exits. Writing from a long-lived helper makes that helper's own exit reset the app's dimming.
- **Timing guarantees hold in the worst case.** For any firm bound (restore within 2 s, no restore for pauses under 1 s), add up the worst-case phase, interval and spawn time. Count a margin under about 10% of the bound as a breach, even when the spec chose the numbers. A bound the spec writes as "about X" (re-applied within about 1 s) is a target, not a bound: work out its worst case, write it down in the ticket or the code comment, and flag it only if it is well past X.
- **Every level is clamped to the 10% floor** before it reaches a gamma write, including levels loaded from disk, computed during ramps, or set by hotkeys.
- **Gamma tables are computed by scaling the captured original curve**, never by building a linear ramp. Level 1.0 must give back the original table exactly.

## No flash

No change to a display's level may show an app brighter than its own level, or jump. `docs/platform/gamma.md` (Timing) has the measurements behind these rules.

- **Dim early, brighten late.** Every path that changes a display's level keeps this order: activation, handover (hide, quit, the window tracker), coming back from lock or sleep, hotkeys, resuming a paused display. A change to a dimmer level happens as soon as it is announced. A change to a brighter level waits until the brighter app's window is in front, and on hide or quit, until the leaving app's windows are off screen.
- **A switch under way owns its displays.** Between `appActivating` and `appActivated`, no other event brightens a display dimmed early for the incoming app; the finished activation sets it right. An app that leaves mid-switch undoes its early dimming.
- **Every fade goes through a `Fader`.** A fade continues from the level on screen, moves at most one refresh along its curve per frame, and shows one frame per refresh. Code that writes a table straight to its target outside a `Fader` is a jump. Only these may jump: a settings change (a slider or "Use default"), a display with no display link, and a re-apply after macOS itself reset the gamma (display change, wake). A re-apply after our own restore (unlock, another user leaving) fades. `restore()` is a jump too: use it only where nobody is watching (lock, sleep, another user) or on the way out (quit, signals). Turning dimming off with the master switch fades.

## Domain language

- Names in code, tests and logs use the terms in `CONTEXT.md`: **app**, **level**, **display owner**, **ignored app**, **paused display**, **unowned display**, **app setting**, **default level**. Flag any word listed under a term's "_Avoid_" (for example `brightness` for a level, or `activeApp` for a display owner).
