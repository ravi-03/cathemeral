# Coding standards

The code reviewer applies these. Anything a tool can check belongs in the `check` script instead.

## Gamma safety

The screen must never be left dim. See `docs/platform/gamma.md` for how gamma works across processes.

- **Every exit path restores gamma.** Any code that writes gamma must restore it on every way out: normal return, thrown errors, early returns, signal handlers, and failure paths in tests and tools. When a check or tool starts child processes that write gamma, its failure path ends those children. A restore call in the parent can't undo a child's writes.
- **The watchdog and any helper that only exists to restore never write gamma**, apart from the restorer's single write-back just before it exits. Writing from a long-lived helper makes that helper's own exit reset the app's dimming.
- **Every level is clamped to the 10% floor** before it reaches a gamma write, including levels loaded from disk, computed during ramps, or set by hotkeys.
- **Gamma tables are computed by scaling the captured original curve**, never by building a linear ramp. Level 1.0 must give back the original table exactly.

## Domain language

- Names in code, tests and logs use the terms in `CONTEXT.md`: **app**, **level**, **display owner**, **ignored app**, **paused display**, **unowned display**, **app setting**, **default level**. Flag any word listed under a term's "_Avoid_" (for example `brightness` for a level, or `activeApp` for a display owner).
