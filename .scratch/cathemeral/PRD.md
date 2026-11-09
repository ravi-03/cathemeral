# Cathemeral: per-app brightness for macOS

Status: ready-for-agent

## Problem Statement

Some apps are much brighter than others. A white document editor sits next to a dark terminal, and a bright web app shares a screen with a dim video player. On macOS the only brightness control is the system brightness, which applies to the whole display and every app on it. To keep a bright app comfortable, I have to press the brightness keys every time I switch to it and again every time I switch away. With two monitors it's worse: each display needs a different brightness depending on what's on it, and switching focus between them means adjusting again.

I want to set a comfortable level for an app once and never think about it again.

## Solution

Cathemeral is a menu bar app. I give an app a level (10% to 100%) once, and from then on, whenever that app is on a display, that display dims to its level. Each display follows its own **display owner**: the app most recently brought to the front on that display or, once that app leaves, the app with the topmost visible window there. Moving focus to another monitor doesn't brighten what I left behind. A display with nothing open on it isn't dimmed.

Dimming works through each display's gamma table, so it stacks on top of the system brightness and never changes it. The brightness keys still work as a global control. Cathemeral needs no permissions.

A sun icon in the menu bar opens a popover with one card per display. Each card shows the display owner and a slider that updates the screen live. Below the cards is every other app with open windows, each with its own slider. Settings has an Apps list of every saved app setting.

The screen must never be left stuck dark. Cathemeral restores the original gamma on quit, crash, hang, sleep, wake and display changes. A small watchdog helper restores it if the app dies or freezes, and a 10% floor keeps the screen readable however things go wrong.

## User Stories

### Setting levels

1. As a user, I want to set a level for an app once, so that the app is dimmed every time I use it without touching the brightness keys.
2. As a user, I want levels to range from 10% to 100%, so that I can dim an app a lot without the screen ever going fully black.
3. As a user, I want any app I haven't given a level to use the default level, so that new apps behave predictably.
4. As a user, I want to change the default level, so that I can make every app I haven't configured a bit dimmer at once.
5. As a user, I want "Use default" to remove an app's setting, so that the app goes back to the default level.
6. As a user, I want setting an app to 100% to mean it's never dimmed, so that I can exempt an app even when the default level is lower.
7. As a user, I want my levels saved across restarts, so that I set them up only once.
8. As a user, I want a hand-edited or corrupted settings file never to black out my screen, so that a bad value can't lock me out.
9. As a user, I want a corrupted settings file to be set aside and the app to start from defaults, so that the app still launches.

### Display ownership

10. As a user, I want the display showing the app I just brought to the front to take that app's level, so that the dimming follows what I'm working in.
11. As a user with two monitors, I want each display to keep its own owner's level when I move focus to the other display, so that a dimmed app doesn't suddenly turn bright while it's still on screen.
12. As a user, I want a display to stop being dimmed for an app once that app quits, so that a display doesn't stay dark for an app that's gone.
13. As a user, I want a display to stop being dimmed for an app once I hide it, so that hiding a bright app brightens what's behind it.
14. As a user, I want a display to stop being dimmed for an app once I minimise or close its last window there, so that the display follows what I can actually see.
15. As a user, I want a display to stop being dimmed for an app once I drag its window to another display, so that the dimming moves with the window.
16. As a user, I want a display whose owner has left to take the level of the topmost app still visible on it, so that whatever I'm now looking at is at its own level.
17. As a user, I want a display with no visible app at all, such as an empty desktop Space, to show at 100%, so that the empty desktop isn't dimmed for no reason.
18. As a user, I want switching to another Space on a display to follow the same rules, so that the dimming follows whatever is on that Space.
19. As a user, I want the app whose window holds the most area on a display to count for that display, so that a window spanning two displays is handled sensibly.
20. As a user, I want Spotlight, the Dock, Notification Center, the login window and Cathemeral itself never to change any display's level, so that opening them doesn't make the screen flicker.
21. As a user, I want two apps side by side on one display both to show the display owner's level, and I accept this limit, so that dimming stays permission-free.
22. As a user, I want each web app installed to the Dock to have its own level separate from its browser, so that I can dim a bright web app without dimming the browser.
23. As a user, I want beta or alternate builds of an app to have their own settings, so that each build behaves as its own app.
24. As a user, I want apps without a bundle ID to still be dimmable, shown by their file name, so that unusual apps aren't left out.

### Responsiveness

25. As a user, I want the screen to start changing within 100 ms of switching apps, so that the switch feels instant.
26. As a user, I want level changes from app switches to ramp over about 150 ms, so that the change isn't a jarring flash.
27. As a user who switches apps rapidly, I want a new switch during a ramp to continue from the current level, so that the screen never jumps.
28. As a user, I want ownership changes that come without an app switch (minimise, close, drag, Space switch) to show within about a second, so that the dimming keeps up without permissions.
29. As a user, I want hide and quit to change the dimming at once, so that the common cases feel instant.
30. As a user, I want Cathemeral to use under 1% CPU when idle, so that it doesn't drain my battery.
31. As a user who has nothing set below 100%, I want the once-a-second window check not to run at all, so that Cathemeral costs nothing when it can't dim anything.

### Menu bar and popover

32. As a user, I want a monochrome sun icon in the menu bar, so that Cathemeral is always one click away and fits the menu bar style.
33. As a user, I want the icon to show whether a display is dimmed right now, so that I can tell at a glance.
34. As a user, I want the icon to show when Cathemeral is turned off, so that I know why nothing is dimming.
35. As a user, I want the icon to show when a display is paused, so that I notice another app has taken over.
36. As a user, I want the popover to show one card per display with its owner, the owner's level and a slider, so that I can see and change what each display is doing.
37. As a user, I want a display card to say "Not dimmed" when nothing is visible on that display, so that the state is clear.
38. As a user, I want a slider to update the screen live while I drag whenever its app owns a display, so that I can tune the level by eye.
39. As a user, I want the slider for an app that owns no display to just save the level, so that I can set it up before I next use the app.
40. As a user, I want the popover to list every other running app with open windows, with a window count and a slider, so that I can set levels for apps I have open.
41. As a user, I want an app without its own setting to show "Default" in the list, so that I know it follows the default level.
42. As a user, I want the window list to refresh while the popover is open and never poll while it's closed, so that it stays current without wasting CPU.
43. As a user, I want a master on/off switch in the popover, so that I can turn all dimming off for a moment.
44. As a user, I want right-clicking the icon to open a quick menu (Enable/Disable, Settings, Quit), so that common actions are fast.
45. As a user, I want Quit to restore normal colours before exiting, so that quitting never leaves my screen dim.
46. As a user, I want "Launch at login" in the popover, so that Cathemeral is always running.
47. As a user, I want the default level slider in the popover footer, so that I can change it without opening Settings.

### Settings

48. As a user, I want an Apps list in Settings with every saved app setting, so that I can review and change levels for apps that aren't open.
49. As a user, I want to remove an app setting from the Apps list, so that I can clean up settings for apps I no longer use.
50. As a user, I want apps that are no longer installed to appear greyed out in the Apps list, so that I can spot stale settings.
51. As a user, I want a slider in the Apps list to update the screen live if that app owns a display, so that it behaves like the popover.
52. As a user, I want Settings to show the steps for recovering a screen stuck dim, so that I can find them if something goes wrong.

### Hotkeys

53. As a user, I want hotkeys to step the frontmost app's level up and down by 10%, so that I can adjust without opening the popover.
54. As a user, I want a hotkey to turn Cathemeral on and off, so that I can disable it instantly.
55. As a user, I want no hotkeys bound by default, so that Cathemeral never takes over a shortcut I already use.
56. As a user, I want to choose the hotkeys in Settings, so that they fit my setup.
57. As a user, I want a level hotkey to create an app setting if the app had none, so that the change sticks.
58. As a user, I want a level hotkey to do nothing when an ignored app is frontmost, so that it never changes something unexpected.
59. As a user, I want a short on-screen indicator on the affected display when I use a level hotkey, so that I can see which app changed and its new level.

### Paused displays

60. As a user running f.lux, Lunar or a calibration tool, I want Cathemeral to notice when another app takes over a display's colours, so that the two apps don't fight.
61. As a user, I want only the affected display to pause, so that my other displays keep dimming.
62. As a user, I want the paused display's card to say another app is controlling its colours and offer Resume, so that I know what happened and how to continue.
63. As a user, I want Resume to dim on top of the other app's colours, so that both can coexist when I choose.
64. As a user, I want a display to pause again if the other app takes over again after Resume, so that Cathemeral never fights in the background.

### Safety

65. As a user, I want normal colours restored when Cathemeral quits normally (menu, Cmd-Q, logout), so that the screen is never left dim.
66. As a user, I want normal colours restored if Cathemeral is terminated by a signal, so that killing it from the terminal is safe.
67. As a user, I want normal colours restored if Cathemeral crashes or is force-killed, so that a crash never leaves the screen dim.
68. As a user, I want normal colours restored within 2 seconds if Cathemeral freezes, so that a hang never leaves the screen dim.
69. As a user, I want dimming to come back if Cathemeral recovers from a freeze, so that I don't have to restart it.
70. As a user, I want short pauses (such as a slow save) never to trigger the freeze restore, so that the screen doesn't flicker.
71. As a user, I want dimming correctly re-applied after sleep and wake, so that my levels survive closing the lid.
72. As a user, I want dimming correctly re-applied after plugging in or unplugging a monitor or dock, so that my levels survive display changes.
73. As a user, I want normal colours while the screen is locked or another user is active, and dimming back when I return, so that the login screen is never dimmed.
74. As a user, I want my display's calibrated colour curve preserved, with dimming applied on top of it, so that my colours stay accurate.
75. As a user, I want displays where dimming can't work (some HDR, Sidecar or AirPlay displays) marked "unsupported", so that I know why nothing happens.
76. As a user whose screen is stuck dim, I want documented recovery steps that work without the app, so that I can always get back to normal.

### Distribution

77. As a user, I want a signed, notarized app, so that macOS lets me open it without warnings.
78. As a user, I want automatic updates, so that I get fixes without reinstalling.
79. As a user, I want Cathemeral to need no permissions for any of the above, so that I can trust it with nothing more than installing it.

## Implementation Decisions

### Architecture

- Cathemeral is a Swift and SwiftUI menu bar app with no Dock icon, for macOS 14 and later on Apple silicon and Intel.
- The code is split into an app target and two local packages. **BrightnessCore** holds all the rules and has no AppKit dependency. **BrightnessPlatform** wraps the macOS APIs behind protocols. A tiny **GammaWatchdog** helper executable is embedded in the app bundle.
- Signals from macOS go into one **DimmingEngine**, which works out a target level per display and hands them to one **BrightnessBackend**. Only the backend touches the screen. Everything runs on the main actor except gamma ramp writes, which run on each display's display-link thread.
- Dimming scales each display's gamma table from its captured original curve, so a level applies to the whole display and the display owner's level wins (ADR 0001). Per-window overlays, the private backlight API and DDC were rejected.
- The `BrightnessBackend` protocol is kept as the extension point for a future per-window overlay backend. The gamma controller is the only implementation for now.

### Modules

- **DimmingEngine** (BrightnessCore). It holds per-display state (owner, paused), the app settings and the preferences. It takes events (app activated, visible windows changed, level set, nudge, use default, display paused, resume, displays changed) and produces target levels per display. Its target-resolving step is pure.
- **Gamma maths** (BrightnessCore). A pure function maps an original curve and a level to a gamma table by scaling every channel by the level. It also defines the ease-out ramp curve.
- **SettingsStore** (BrightnessCore). It loads and saves app settings and preferences as one JSON file in Application Support, under a Cathemeral folder.
- **ActivationMonitor** (BrightnessPlatform). It reports the frontmost app's ID, PID and the display holding its key window on every activation. It also reports hide and terminate events.
- **FrontWindowTracker** (BrightnessPlatform). Once a second it lists the apps visible on each display, topmost first, from the on-screen window list (layer-0 windows only). It assigns each window to the display it overlaps most and reports the result to the engine. It runs only while Cathemeral is enabled and some app setting or the default level is below 100%.
- **WindowInventory** (BrightnessPlatform). It lists running apps with on-screen windows and their window counts for the popover, on open and every 2 seconds while the popover is open.
- **DisplayMonitor** (BrightnessPlatform). It reports display add, remove and reconfigure, sleep and wake, and session lock and unlock, debounced by 500 ms.
- **HotkeyService** (BrightnessPlatform). It registers user-chosen global hotkeys (level up, level down, on/off) with no Accessibility permission. Nothing is bound by default.
- **GammaController** (BrightnessPlatform). It implements `BrightnessBackend`. It captures each display's original curve (only while our curve isn't applied), ramps to targets on the display link, reads each write back, and restores. It drives paused-display detection.
- **SafetyNet and GammaWatchdog**. These restore gamma on normal quit, on termination signals, and through the watchdog helper on crash or hang.
- **StatusItemController and the popover views**. These show the menu bar icon, the popover, Settings and its Apps list.
- **LoginItem**. It handles launch at login.

### Domain rules (see CONTEXT.md for terms)

- **Ownership.** An activation makes the app the owner of the display holding its key window, unless it's an ignored app. When the visible windows change, an owner with no visible window on its display loses it. Each display without an owner then passes to its topmost visible app, or stays unowned if no app is visible there. Focus moving to another display never changes ownership.
- **Ignored apps** are a fixed list that users can't edit: Spotlight, the Dock, Notification Center, the login window and Cathemeral itself.
- **Target resolution.** If Cathemeral is off, every display gets 100% (restore). Otherwise each display that isn't paused gets its owner's app setting level, or the default level if the owner has none, clamped to the floor. An unowned display gets 100%. A paused display gets no target.
- **App identity.** An app is identified by its bundle ID, or by its executable path if it has none. Web apps installed to the Dock and beta builds are separate apps.
- **Floor.** The 10% minimum level is a fixed constant, not a setting. Every level is clamped to it, including levels loaded from the settings file.
- **App settings** hold only a level (plus a cached display name and a timestamp). There is no warmth and no enabled flag. "Use default" deletes the app setting.
- **Preferences** hold the on/off switch, the default level, the ramp duration, the opt-in to show window titles, and the hotkey bindings.

### Interactions

- **Slider:** a slider applies at up to 30 Hz with no ramp while its app owns a display. Otherwise it only updates the model. The value is saved 300 ms after the last change.
- **Hotkeys:** a level hotkey steps the frontmost app's level by ±10% with a 150 ms ramp and saves it. It does nothing if the frontmost app is an ignored app. An optional indicator appears on that app's display for 1 second.
- **Ramps:** an activation ramps over 150 ms with an ease-out curve. A new target mid-ramp starts from the current level. Display changes re-apply without a ramp, because macOS has already reset the gamma.
- **Display changes:** after a reconfiguration (debounced 500 ms) or a wake, the gamma controller restores ColorSync settings, re-captures originals for every online display and drops removed ones. The engine then re-applies its targets.
- **Lock and user switch:** gamma is restored when the session resigns active and re-applied when it becomes active again.

### Paused displays

- When any other gamma-writing process exits (f.lux quitting, our own restorer), WindowServer silently resets every display, and nothing notifies us. So while a display is dimmed, the controller also reads its table back on the 1 Hz window tick. A table equal to the captured original means it was reset: re-apply silently, without counting a mismatch. A table equal to what we wrote is fine. Anything else counts as a mismatch.
- After each write the controller reads the table back. Three mismatches in a row mean another app owns that display's gamma. That display is paused and gets no more writes, while other displays carry on.
- Resume re-captures the display's current curve as its original and re-applies the owner's level. Another mismatch pauses it again. Nothing resumes automatically.

### Safety net

- A normal quit restores ColorSync settings for all displays. Termination signals are handled the same way.
- If the app dies for any reason, including `kill -9`, macOS itself resets the gamma it set (measured: 65 ms). The spike (ticket 01) showed that gamma belongs to the WindowServer connection that wrote it: `CGDisplayRestoreColorSyncSettings` only undoes the caller's own gamma, the last write wins across processes, and when any process that wrote gamma exits, every display is reset to ColorSync defaults.
- The watchdog helper is launched at startup and holds a pipe to the app. The app writes a heartbeat byte every 500 ms from the main run loop. The watchdog waits with a **1.5-second** timeout. End-of-file means the app died: macOS has already restored, so the watchdog just exits. A timeout means the app is hung: the watchdog spawns a one-shot **restorer** process that writes each display's current table back unchanged and exits, which makes WindowServer reset every display. The watchdog then signals back. If the app recovers, it re-applies its targets with a ramp. The watchdog itself never writes gamma, because its own exit would wipe the app's dimming. If the watchdog dies, the app relaunches it.
- App Nap is disabled for the heartbeat through a user-initiated activity.

### Persistence

- There is one JSON file with a schema version. Writes are atomic and debounced 300 ms after the last change. A corrupt file is renamed with a date suffix and the app starts from defaults.

### Distribution

- Developer ID signed and notarized, Hardened Runtime, no sandbox, updates through Sparkle 2 with an EdDSA-signed appcast. The sandbox is left off to keep the door open for a future overlay backend.

### Open questions for the spike

These must be answered before the build relies on them. Answers from ticket 01 (M1, macOS 26.3); details and raw output are in that ticket and on the `prototype/spike` branch:
- ~~Can `CGDisplayRestoreColorSyncSettings` called from the watchdog process reset gamma set by the app process?~~ **No.** The watchdog uses a one-shot restorer process instead (see Safety net).
- ~~Does macOS restore gamma by itself when the process that set it exits?~~ **Yes**, 65 ms after a SIGKILL. It also resets every display when *any* gamma writer exits (see Paused displays).
- Does Night Shift go through the gamma table? (It's believed not to, in which case it stacks with dimming rather than pausing a display.) *Open: ticket 02.*
- Actual switch latency, measured with a 240 fps video of Cmd-Tab. *Software part measured: activation notification to first gamma write, 4.4 ms median and 11.4 ms at p95. Glass-to-glass: ticket 02.*
- ~~Actual cost of one on-screen window list call with about 50 windows.~~ **About 0.9 ms median and 2.9 ms at p95** with 58 layer-0 windows, roughly 0.1% of a core at 1 Hz.
- The bundle ID prefix (proposed: `io.github.ravi-03.cathemeral`) must be fixed before the first release.

## Testing Decisions

- **Good tests check external behaviour only.** A test drives a module through its public interface and asserts on what comes out: target levels per display, what was saved, the gamma table produced. It never asserts on internal state or private methods, so the internals can be refactored freely.
- **Main seam: DimmingEngine.** Tests construct it with a recording fake `BrightnessBackend`, an in-memory settings store and a controllable clock. They feed it scripted events (activations, visible-window snapshots, slider changes, nudges, pauses, resumes, display changes) and assert the targets the fake backend received and their timing. This covers:
  - ownership and handover across activations, hides, quits, minimises, moves and Space switches
  - unowned displays at 100%, and ignored apps never becoming owners
  - default level versus app setting, "Use default", and the 10% clamp
  - paused displays getting no target, and Resume
  - live slider updates only for display owners, the hotkey target and the ignored-app no-op
  - the on/off switch, and save debouncing through the clock
  - the target-resolution truth table: enabled × app setting present × owned/unowned/paused × number of displays
- **Second seam: gamma maths, as a pure function.** At level 1.0 the original curve must come back byte-for-byte. At level 0.4 every entry must be scaled. The ramp curve is checked at its endpoints, and an interrupted ramp must continue from the current level.
- **SettingsStore** is tested through its load and save interface: round-tripping, schema migration, renaming a corrupt file, and clamping levels below 10% on load.
- **Not unit-tested:** the BrightnessPlatform wrappers, the watchdog and the UI. They're covered by the spike and a manual checklist:
  - latency, using a 240 fps video
  - external monitor, dock and undock, sleep and wake
  - `kill -9` (restore by macOS) and `kill -STOP` (restore by the watchdog's restorer within 2 seconds)
  - dragging a window across monitors (followed within 1 second)
  - a Space switch, and f.lux taking over (pause, then Resume)
  - idle CPU under 1% in Instruments
- **Prior art:** none yet, because the repo has no code. These tests set the pattern.

## Out of Scope

- Dimming only one app's windows while others on the same display stay bright (per-window overlays). This is a possible future backend behind `BrightnessBackend` and would need the Accessibility permission.
- Warm tint (F8) and schedules (F5). Night Shift already covers both.
- Real dark mode, colour inversion (F9) or code injection into other apps.
- Changing the system brightness or backlight, including through the private DisplayServices API or DDC.
- A user-editable ignored-app list.
- Grouping variants (such as Chrome and Chrome Beta) under one setting.
- Per-site dimming inside browsers, except through web apps installed to the Dock.
- Mac App Store distribution.
- Showing window titles by default. It's an opt-in that needs the Screen Recording permission.

## Further Notes

- Glossary: `CONTEXT.md`. Dimming-model decision: `docs/adr/0001-per-display-gamma-dimming.md`. The full HLD and LLD, with diagrams, is in the design doc (Claude Docs: "Cathemeral: per-app brightness for macOS — HLD & LLD").
- Suggested build order, from the design doc's milestones: spike (2 days), MVP (1 week: status item and popover, app settings, display ownership, JSON store, hotkeys, crash-safe restore, launch at login, Apps list), polish (3 days: multi-display rules, paused displays), then release (signing, notarization, Sparkle).
- The spike should come first and block everything else, because its answers about the watchdog and Night Shift could change the safety-net design.
