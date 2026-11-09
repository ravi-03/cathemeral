# 02: Spike: manual checks

**What to build:** The checks only a person with this Mac and its hardware can do, using the probe script from ticket 01. Record each result in this ticket under `## Comments`.

**Blocked by:** 01 (Spike: automated platform checks)

**Status:** ready-for-human

- [ ] Night Shift: toggle Night Shift on and off while the probe runs. Record whether the gamma table changes. Unchanged means Night Shift stacks with dimming. Changed means it would pause a display, and the edge-case row in the PRD needs updating.
- [ ] External monitor: plug in and unplug an external display and a dock. Record the gamma state before and after.
- [ ] Sleep and wake: close and open the lid. Record whether the gamma resets on wake.
- [ ] Optional: film Cmd-Tab between a dimmed and an undimmed app at 240 fps and count the frames to the first visible change. Target: under 100 ms.
- [ ] Bundle ID prefix decided (proposed: `io.github.ravi-03.cathemeral`), and recorded in the PRD.
