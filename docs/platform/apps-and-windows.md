# Apps and windows on macOS

How macOS reports which app is in front and where its windows are, as measured on this Mac. Apple documents little of it. Activation timing, which drives the no-flash rules, is in `gamma.md` (Timing).

## The frontmost app

- **`NSWorkspace.frontmostApplication` can disagree with the screen.** Opening two apps 60 ms apart with `open -b` can leave it naming one app while the other's window is on top (tickets 04 and 05). Read the window list (`Displays.normalWindows()`) when you need to know what is showing.
- **Level hotkeys act on `frontmostApplication`** (`Displays.frontmostApp()`, ticket 12). A hotkey press is a single deliberate action, not a burst, so the disagreement above shouldn't arise.

## Global hotkeys

- **`RegisterEventHotKey` (Carbon) needs no Accessibility or Input Monitoring permission.** macOS delivers only the registered combinations. Since macOS 15 it refuses a combination whose only modifiers are Option or Option-Shift. `HotkeyService` has the details.

## Not yet verified

- Whether `frontmostApplication` reports Spotlight while its panel is open, or the app behind it. If it reports the app behind it, a level hotkey changes that app, which breaks the ignored-app rule (ticket 12's checks by hand). Record the answer here.
- Whether holding a registered hotkey repeats it. `HotkeyService` handles only `kEventHotKeyPressed`, so either way a press steps at least once.
