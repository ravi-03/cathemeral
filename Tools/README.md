# Tools

End-to-end checks on the real screen. Not shipped in the app, and not run by `scripts/check`, because they switch apps and dim the display.

- **`./e2e.sh`** runs the real DimmingEngine, GammaController, ActivationMonitor and FrontWindowTracker, switches between Terminal and Finder, and reads every result back with `peek`. It prints `ok` or `FAIL` per step and exits non-zero on any failure. It takes about 30 seconds.
- **`switch-timing`** (`swift run switch-timing <bundle-id> <bundle-id> [rounds]`) switches between two apps and fails if either app is ever shown brighter than its own level (brightening must wait until the new app's window is in front, and dimming must be done by then), if a switch jumps instead of fading, or if rapid switching back and forth ever jumps. Run it while Cathemeral or the harness is dimming, with different levels for the two apps. `e2e.sh` runs it. It never writes gamma.
- **`peek`** (`swift run peek [--built-in]`) prints each display's gamma peak: about 1.0 undimmed, about the level when dimmed. It never writes gamma, so running it changes nothing.
- **`harness`** is the engine with no UI (plus the activation monitor and window tracker), driven by commands on stdin (`set`, `activate`, `hide`, `displays-changed`, `suspend`, `unsuspend`, `quit`). The command list is at the top of `Sources/harness/main.swift`. Extend `e2e.sh` with new scenarios as tickets add behaviour (ramps, handover, displays, signals).

Both `e2e.sh` and `harness` follow the gamma-safety standards in `CODING_STANDARDS.md`: every way out ends the harness, whose exit makes macOS reset its gamma.
