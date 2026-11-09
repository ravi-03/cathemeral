# 05: Smooth ramps

**What to build:** Level changes caused by app switches and hotkeys ramp over 150 ms with an ease-out curve, written on each display's display-link tick instead of jumping. A new target that arrives mid-ramp starts from the level currently on screen, so rapid Cmd-Tab never jumps. Slider drags and display re-applies stay un-ramped.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-agent

- [ ] Switching between a 40% app and a 100% app visibly fades instead of flashing.
- [ ] Rapid Cmd-Tab back and forth never jumps in brightness.
- [ ] Slider drags still apply immediately.
- [ ] Gamma maths tests cover the ramp curve's endpoints, and show an interrupted ramp continuing from the current level.
- [ ] Each frame is computed from the original curve and never compounds on the previous frame.
