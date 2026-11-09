# Cathemeral

Per-app brightness for macOS.

Cathemeral is a menu bar app that dims each display to a level you choose for the app in front on that display. Set Notion to 40% once, and the screen showing Notion dims to 40% whenever it's there, without touching the brightness keys.

> **Status:** design phase. There is no code yet. The design is settled; the next step is a two-day spike to measure switch latency and prove crash-safe restore.

## How it works

- **One level per app.** Each app has its own level (10–100%) or uses the default level. Apps are identified by bundle ID.
- **One owner per display.** Each display shows the level of its *display owner*: the app most recently brought to the front there or, once that app leaves, the app with the topmost visible window. A display with no visible app isn't dimmed.
- **Gamma, not backlight.** Dimming scales each display's gamma table, so it stacks on top of the system brightness and never touches it. It needs only public APIs and no permissions.
- **Never stuck dark.** Gamma is restored on quit, crash, hang, sleep/wake and display changes. A small watchdog helper restores it if the app dies or freezes.

Target: macOS 14+, Apple silicon and Intel. Built in Swift and SwiftUI, distributed as a notarized Developer ID app.

## If your screen is stuck dim

The dimming lives only in memory, so a restart always clears it. The 10% floor keeps the screen readable enough for these steps, fastest first:

1. **Quit the app:** menu bar icon → Quit, or ⌥⌘Esc → Cathemeral → Force Quit.
2. **Reload the colour profile:** System Settings → Displays → Color profile. Pick another profile, then the original again.
3. **Sleep and wake the display:** close and open the lid, or unplug and replug the external monitor.
4. **Log out or restart:** always works.

The brightness keys, Night Shift and True Tone won't fix it, because they don't touch the gamma table.

## Project docs

- [`CONTEXT.md`](CONTEXT.md): the glossary (display owner, app setting, level, paused display, and so on). Use these terms in code, issues and discussion.
- [`docs/adr/`](docs/adr/): architecture decision records, starting with [ADR 0001: per-display gamma dimming](docs/adr/0001-per-display-gamma-dimming.md).
- [`docs/agents/`](docs/agents/): configuration for the agent skills (issue tracker, triage labels, domain docs).
- Issues and PRDs live as local markdown files under `.scratch/`.
