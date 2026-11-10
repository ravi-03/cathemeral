# 04: Saved app settings and default level

**What to build:** App settings and preferences survive a restart. They're saved to one JSON file in Application Support (Cathemeral folder) with a schema version. Writes are atomic and debounced 300 ms after the last change. A corrupt file is renamed with a date suffix and the app starts from defaults. Any level below 10% in the file is clamped to 10% on load. The popover footer gets the "Default for new apps" slider, and each card gets "Use default", which removes the app setting.

**Blocked by:** 03 (Tracer bullet: frontmost app dims its display)

**Status:** ready-for-human

- [ ] Set Notion to 40%, quit, relaunch, bring Notion to the front: the display dims to 40%.
- [x] Changing the default level changes every app without an app setting. Apps with one keep their own level.
- [x] "Use default" removes the app setting, and the app then follows the default level.
- [x] A corrupted settings file is set aside and the app launches with defaults.
- [x] A level of 0 written into the file by hand loads as 10%.
- [x] SettingsStore tests cover round-trip, corrupt-file recovery, the clamp on load, and the schema version.
- [x] DimmingEngine tests confirm saves are debounced through the test clock.

## Comments

**2026-11-10 (agent):** Implemented. Covered by tests: default level vs app setting, "Use default", corrupt-file set-aside (`settings-corrupt-<date>.json`; a newer schema version is set aside too), clamp on load, schema version, and debounced saves through the test clock. Pending saves are flushed on quit and on termination signals, after gamma is restored. Left for a human: the Notion 40% quit-and-relaunch check in the real app. Deferred: the PRD's cached display name and timestamp per app setting (ticket 11 can add them with a schema bump), and schema migration (only version 1 exists).
