# Dim whole displays through the gamma table, not individual windows

We dim by scaling each display's gamma table from its captured original curve, so a level applies to a whole display and the display owner's level wins. Two apps side by side on one display therefore share the owner's level. We chose this because it uses only public APIs, needs no permissions, works on every display type, and changes within one frame of an app switch.

How gamma tables behave across processes (the last write wins, any writer's exit resets the display, a restore call only undoes the caller's own writes) is in `docs/platform/gamma.md`.

## Considered Options

- **Per-window overlays** (a dark, click-through window over each of another app's windows). Rejected for now: following other apps' windows needs the Accessibility permission, and overlays lag behind window moves and resizes. The `BrightnessBackend` protocol is kept so an overlay backend can be added later as a second backend for "windows only" dimming.
- **Private DisplayServices backlight API.** Rejected: it is private, breaks across macOS updates, and would fight the user's own brightness keys.
- **DDC/CI to external monitors.** Rejected: it doesn't work on the built-in display, many monitors and docks don't support it, and it is too slow for sub-100 ms switches.
