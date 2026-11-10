# cathemeral

**Real screen:** after changing `ActivationMonitor`, `GammaController`, `Fader`, or when `DimmingEngine` applies levels, run `Tools/e2e.sh`. It takes over the screen for about 30 s, so `scripts/check` and CI can't run it. See `Tools/README.md`.

## Agent skills

### Issue tracker

Issues and PRDs live as local markdown files under `.scratch/<feature-slug>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`), recorded as a `Status:` line in each issue file. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` + `docs/adr/` at the repo root. See `docs/agents/domain.md`.
