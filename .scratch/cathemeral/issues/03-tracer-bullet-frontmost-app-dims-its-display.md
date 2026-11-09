# 03: Tracer bullet: frontmost app dims its display

**What to build:** The thinnest end-to-end Cathemeral. The project exists as an app target plus the BrightnessCore and BrightnessPlatform packages, with a test target. A monochrome sun icon sits in the menu bar. Clicking it opens a popover with one card for the built-in display, showing its display owner and a level slider (10–100%). Bringing an app to the front makes it that display's owner, and the display dims to the app's level. Levels live in memory for now. Moving the slider changes the level live. Quit restores the original gamma.

The domain rules come from CONTEXT.md and the PRD: apps are identified by bundle ID (executable path if none), and ignored apps (Spotlight, Dock, Notification Center, login window, Cathemeral itself) never become display owners. The gamma maths scales the captured original curve, never a linear ramp.

**Toolchain note (from ticket 01):** this Mac has only the Command Line Tools, so `xcodebuild` isn't available. Install Xcode, or build the app with SwiftPM and wrap it into an `.app` bundle with a script.

**Blocked by:** 01 (Spike: automated platform checks)

**Status:** ready-for-agent

- [ ] The project builds, launches as a menu bar app with no Dock icon, and the test suite runs from one command.
- [ ] One `check` script runs build, tests and `swift format lint`, and exits non-zero on any failure. A pre-commit hook and a GitHub Actions job both run it.
- [ ] Bringing an app with a level of 40% to the front dims the built-in display to 40%. Bringing a 100% app to the front restores it.
- [ ] Opening the popover (Cathemeral itself) or Spotlight leaves the display's level unchanged.
- [ ] Moving the owner's slider in the popover changes the display live.
- [ ] Levels below 10% can't be set.
- [ ] Quit restores the original gamma.
- [ ] DimmingEngine tests, using a recording fake backend, an in-memory store and a test clock, cover: activation makes the owner, ignored apps don't, an app without a setting uses the default level, and the 10% clamp.
- [ ] Gamma maths tests: level 1.0 returns the original byte-for-byte, and level 0.4 scales every entry.
