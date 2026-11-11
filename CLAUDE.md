# cathemeral

**Real screen:** after changing `GammaController`, `ActivationMonitor`, `FrontWindowTracker` or `SafetyNet` (BrightnessPlatform), `Fader`, `App/GammaWatchdog`, or how `DimmingEngine` applies levels, run `Tools/e2e.sh` in the background, or just the affected section (`Tools/e2e.sh paused`). It takes over the screen for about 2.5 minutes, so `scripts/check` and CI can't run it. See `Tools/README.md`.

**macOS behaviour:** read `docs/platform/` before relying on how macOS reports apps, windows or gamma. It holds what was measured on this Mac, including where the APIs mislead.

## Agent skills

### Issue tracker

Issues and PRDs live as local markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
