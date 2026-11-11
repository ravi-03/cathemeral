# cathemeral

**Real screen:** after changing `BrightnessPlatform`, `Fader`, `App/GammaWatchdog`, or how `DimmingEngine` applies levels, run `Tools/e2e.sh` in the background, or just the affected section (`Tools/e2e.sh paused`). It takes over the screen for about 2.5 minutes, so `scripts/check` and CI can't run it. See `Tools/README.md`.

## Agent skills

### Issue tracker

Issues and PRDs live as local markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
