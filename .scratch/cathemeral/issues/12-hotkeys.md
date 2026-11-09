# 12: Hotkeys

**What to build:** Global hotkeys, chosen by the user in Settings, with none bound by default. Level up and level down step the frontmost app's level by 10% with a 150 ms ramp and save it, creating an app setting if the app had none. If the frontmost app is an ignored app, a level hotkey does nothing. An on/off hotkey toggles all of Cathemeral. A level hotkey shows a small indicator ("Notion 40%") for 1 s on the affected display. Hotkeys use an API that needs no Accessibility permission.

**Blocked by:** 11 (Settings window and Apps list)

**Status:** ready-for-agent

- [ ] A fresh install has no hotkeys bound.
- [ ] The user can bind, change and clear each hotkey in Settings, and bindings survive a restart.
- [ ] Level down on Notion at 40% takes it to 30% with a ramp, and the indicator appears on Notion's display.
- [ ] Levels never go below 10% or above 100% through hotkeys.
- [ ] A level hotkey with Spotlight frontmost changes nothing.
- [ ] The on/off hotkey toggles dimming on every display.
- [ ] DimmingEngine tests cover a nudge on the frontmost app, creating a missing app setting, clamping, and the ignored-app no-op.
