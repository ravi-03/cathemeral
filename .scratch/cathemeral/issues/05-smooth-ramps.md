# 05: Smooth ramps

**What to build:** Level changes caused by app switches and hotkeys ramp over 150 ms with an ease-out curve, written on each display's display-link tick instead of jumping. A new target that arrives mid-ramp starts from the level currently on screen, so rapid Cmd-Tab never jumps. Slider drags and display re-applies stay un-ramped.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** done

- [x] Switching between a 40% app and a 100% app visibly fades instead of flashing.
- [x] Rapid Cmd-Tab back and forth never jumps in brightness.
- [x] Slider drags still apply immediately.
- [x] Gamma maths tests cover the ramp curve's endpoints, and show an interrupted ramp continuing from the current level.
- [x] Each frame is computed from the original curve and never compounds on the previous frame.

## Comments

**2026-11-10 (agent):** Implemented. App switches fade over 150 ms with a cubic ease-out, and settings changes (sliders, "Use default") apply straight away.

- `Ramp` (the curve) and `Fader` (per-display fade state) are pure, in BrightnessCore, and unit-tested. `GammaController` drives a `Fader` per display from its display link and scales the captured original by each frame's level.
- `Fader` rules, each from a failure seen on the real screen: a new target fades on from the last frame actually shown, not from where the curve says the screen should be; each frame moves at most one refresh along the curve, so a busy main thread slows a fade instead of making it jump; only one frame per refresh, and a frame whose write landed late counts for the refresh it really shows at.
- The first frame of a fade on an idle display is written straight away, so dimming early keeps its head start. Ticks wait while a gamma write is in flight rather than replacing it.
- The display-link ticks run on the main run loop, and writes run on a background queue. The PRD's Architecture line is updated to match.
- `Tools/switch-timing` (run by `e2e.sh`) checks that each switch fades (several levels, no step over 40% of the change, about 30% expected at 60 Hz), and that rapid switching back and forth never steps more than 40% of the gap between the two apps' levels. It passes on the harness (Terminal and Finder) and on the real app (Notion and iTerm2).

Left for a human: watch a 40% to 100% switch fade, hold Cmd-Tab back and forth (the tool uses `open`, not Cmd-Tab), and drag the popover slider to check it still applies immediately.

Later tickets: re-applying after display changes (07) should call `restore()` first, which now clears all per-display state. Hotkeys (12) need a ramped entry point in the engine, because `setLevel` applies straight away.

**2026-11-10 (agent):** The fade, rapid Cmd-Tab and slider checks pass by hand (confirmed by the user). All boxes ticked.
