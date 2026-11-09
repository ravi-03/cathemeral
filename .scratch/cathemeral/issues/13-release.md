# 13: Release

**What to build:** A version people can install and keep updated. Ship Cathemeral as a Developer ID-signed, notarized app with Hardened Runtime and no sandbox, using the bundle ID decided in ticket 02. Updates come through Sparkle 2 with an EdDSA-signed appcast. Run the PRD's manual QA checklist on the release build.

**Blocked by:** 02 (Spike: manual checks), 05 (Smooth ramps), 06 (Ownership follows windows), 08 (Full popover and status icon), 09 (Crash and hang safety net), 10 (Paused and unsupported displays), 12 (Hotkeys)

**Status:** ready-for-human

- [ ] The bundle ID is final and matches ticket 02's decision.
- [ ] A downloaded build opens with no Gatekeeper warning.
- [ ] Sparkle finds and installs an update from the signed appcast.
- [ ] Manual QA checklist passes: latency, external monitor, dock and undock, sleep and wake, `kill -9`, `kill -STOP`, dragging across monitors, Space switch, f.lux pause and Resume, idle CPU under 1%.
- [ ] The README's status section is updated from "design phase".
