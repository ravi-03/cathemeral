# 03: Tracer bullet: frontmost app dims its display

**What to build:** The thinnest end-to-end Cathemeral. The project exists as an app target plus the BrightnessCore and BrightnessPlatform packages, with a test target. A monochrome sun icon sits in the menu bar. Clicking it opens a popover with one card for the built-in display, showing its display owner and a level slider (10–100%). Bringing an app to the front makes it that display's owner, and the display dims to the app's level. Levels live in memory for now. Moving the slider changes the level live. Quit restores the original gamma.

The domain rules come from CONTEXT.md and the PRD: apps are identified by bundle ID (executable path if none), and ignored apps (Spotlight, Dock, Notification Center, login window, Cathemeral itself) never become display owners. The gamma maths scales the captured original curve, never a linear ramp.

**Toolchain:** Xcode 27.2 (Swift 6.4.2) is installed and selected. `swift test` runs both XCTest and Swift Testing, and `swift format` and `actool` work. Recommended layout: BrightnessCore, BrightnessPlatform and the watchdog as local Swift packages tested with `swift test`, plus one thin Xcode app target that bundles them into the `.app`.

**Blocked by:** 01 (Spike: automated platform checks)

**Status:** done

- [x] The project builds, launches as a menu bar app with no Dock icon, and the test suite runs from one command.
- [x] One `check` script runs build, tests and `swift format lint`, and exits non-zero on any failure. A pre-commit hook and a GitHub Actions job both run it.
- [x] Bringing an app with a level of 40% to the front dims the built-in display to 40%. Bringing a 100% app to the front restores it.
- [x] Opening the popover (Cathemeral itself) or Spotlight leaves the display's level unchanged.
- [x] Moving the owner's slider in the popover changes the display live.
- [x] Levels below 10% can't be set.
- [x] Quit restores the original gamma.
- [x] DimmingEngine tests, using a recording fake backend, an in-memory store and a test clock, cover: activation makes the owner, ignored apps don't, an app without a setting uses the default level, and the 10% clamp.
- [x] Gamma maths tests: level 1.0 returns the original byte-for-byte, and level 0.4 scales every entry.

## Comments

### 2026-11-10: implementation (agent)

Layout: `Packages/BrightnessCore` (engine, levels, gamma maths, 15 Swift Testing tests), `Packages/BrightnessPlatform` (GammaController, ActivationMonitor, Displays), and a thin app target `App/Cathemeral` in a hand-written `Cathemeral.xcodeproj` (synchronized folder, local package references). `scripts/check` runs `swift format lint --strict`, `swift test` and `xcodebuild`. It was seen to exit 1 on a lint failure and on a failing test. The pre-commit hook is `.githooks/pre-commit` (enable with `git config core.hooksPath .githooks`). The CI job is `.github/workflows/check.yml`. **It has not run yet**, and the `macos-latest` toolchain may differ from Xcode 27.2.

How each box was verified:
- **Real display, real code.** A scratch harness ran the real DimmingEngine, GammaController and ActivationMonitor with Terminal at 40% and Finder at 100%, switching apps with `open -b`. A separate process that never writes gamma read the main display's peak back each time:
  - Before: 1.0000.
  - Terminal in front: 0.4000.
  - Finder in front: 1.0000.
  - Terminal again: 0.4000.
  - Spotlight activation: 0.4000.
  - Owner's level set to 55%: 0.5500.
  - Set to 2%: 0.1000.
  - After quit: 1.0000.
- **The built app** has `LSUIElement` set, runs as a `UIElement` (no Dock icon) and quits cleanly from an Apple Event and from SIGTERM.

**Checked by hand by the user on 2026-11-10 (boxes now ticked):** open the real popover over a dimmed app and confirm the level doesn't change, then drag the owner's slider and watch the display follow. Both work: the level held with the popover open, and the display followed the slider.

Notes for later tickets:
- **Signals (ticket 09):** SIGTERM, SIGINT and SIGHUP already restore gamma through dispatch signal sources in `AppDelegate`. Ticket 09 only needs to verify that.
- **Clock:** the engine takes a `DimmingClock` but doesn't read it yet. Debounce (04) and ramps (05) are its first users.
- **Displays (ticket 07):** an activation goes to the display that the app's frontmost layer-0 window overlaps most, as the PRD describes. Until 07 adds a card per display, an app on an external display dims that display with no card to adjust it.
- **Restore:** quit restores ColorSync settings, not the captured originals. That matches the PRD's safety net.

