// Runs the real DimmingEngine, GammaController, ActivationMonitor and FrontWindowTracker, like the app does but
// with no UI, and takes commands on stdin so a script can drive it:
//
//   set <bundle-id> <fraction>   save an app setting (live if the app owns a display)
//   activate <bundle-id>         report an activation directly, as if that app came to the front
//                                on the built-in display (use for ignored apps like Spotlight,
//                                which `open` can't bring forward)
//   hide <bundle-id>             hide that app, as Cmd-H does
//   displays-changed             report a display change, as after plugging in a monitor or waking
//   suspend                      suspend dimming, as when the screen locks
//   unsuspend                    stop suspending, as when the screen unlocks (fades back)
//   stall <seconds>              block the main thread, as a short stall in the app would
//   resume                       resume the built-in display, as its card's Resume button does
//   status                       print `status paused`, `status unsupported` or `status dimming`
//                                for the built-in display
//   quit                         restore gamma and exit
//
// Usage: `harness <path-to-GammaWatchdog>`. Like the app, it runs the real `SafetyNet`: gamma is
// restored on SIGTERM, SIGINT and SIGHUP, and the watchdog restores it if the harness hangs (try
// `kill -STOP`). It is also restored on `quit` and on end of input. If it dies any other way,
// macOS resets its gamma when it exits (docs/platform/gamma.md).
//
// It prints `READY` once listening, then one line per event.
import AppKit
import BrightnessCore
import BrightnessPlatform

func say(_ line: String) {
    print(line)
    fflush(stdout)
}

/// The engine wired to the real screen, plus the commands that drive it.
@MainActor final class Harness {
    private let engine = DimmingEngine(
        backend: GammaController(), store: InMemorySettingsStore(), clock: SystemClock(),
        selfID: AppID(bundleID: "cathemeral.harness"), displays: Displays.active)
    private lazy var safetyNet = SafetyNet(
        watchdog: URL(fileURLWithPath: CommandLine.arguments[1]),
        beforeExit: { [unowned self] in restoreAndExit("termination signal") },
        onRestoredFromOutside: { [unowned self] in
            engine.restoredFromOutside()
            say("restored from outside: fading back")
        }
    )
    private lazy var activations = ActivationMonitor(
        onActivating: { [unowned self] app, display in engine.appActivating(app, on: display) },
        onActivation: { [unowned self] app, display in report(app, on: display) },
        onLeft: { [unowned self] app, visibleApps in
            engine.appLeft(app, visibleApps: visibleApps)
            say("left \(app): owner \(engine.owner(of: Displays.builtIn)?.id.rawValue ?? "none")")
        }
    )
    private lazy var windowTracker = FrontWindowTracker { [unowned self] visibleApps in
        engine.visibleAppsChanged(visibleApps)
    }

    func start() {
        safetyNet.start()
        activations.start()
        windowTracker.start()
    }

    func run(_ command: [Substring]) {
        switch (command.first, command.count) {
        case ("set", 3):
            guard let fraction = Double(command[2]) else { return say("bad fraction: \(command[2])") }
            engine.setLevel(Level(fraction), for: AppID(bundleID: String(command[1])))
            say("set \(command[1]) \(Level(fraction))")
        case ("activate", 2):
            let id = AppID(bundleID: String(command[1]))
            report(App(id: id, name: id.rawValue), on: Displays.builtIn)
        case ("hide", 2):
            // `hide()` can return false even when the app hides, so the `left` line is the result.
            for running in NSRunningApplication.runningApplications(withBundleIdentifier: String(command[1])) {
                _ = running.hide()
            }
            say("hide \(command[1]) requested")
        case ("displays-changed", 1):
            let active = Displays.active
            engine.displaysChanged(to: active)
            say("displays changed: \(active.map(\.description).joined(separator: ", "))")
        case ("suspend", 1):
            engine.setSuspended(true)
            say("suspended")
        case ("unsuspend", 1):
            engine.setSuspended(false)
            say("unsuspended")
        case ("stall", 2):
            guard let seconds = Double(command[1]) else { return say("bad seconds: \(command[1])") }
            Thread.sleep(forTimeInterval: seconds)
            say("stalled \(command[1]) s")
        case ("resume", 1):
            engine.resume(Displays.builtIn)
            say("resumed")
        case ("status", 1):
            say("status \(engine.status(of: Displays.builtIn))")
        case ("quit", 1):
            restoreAndExit("quit")
        default:
            say("unknown command: \(command.joined(separator: " "))")
        }
    }

    /// Returns `Void`, not `Never`: Swift 6.2 (Xcode 26) can't infer `assumeIsolated { … }` around a
    /// `Never` call.
    func restoreAndExit(_ why: String) {
        engine.restore()
        say("restored (\(why))")
        exit(0)
    }

    private func report(_ app: App, on display: DisplayID) {
        engine.appActivated(app, on: display)
        say("activated \(app.id) on \(display): owner \(engine.owner(of: display)?.id.rawValue ?? "none")")
    }
}

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: harness <path-to-GammaWatchdog>\n".utf8))
    exit(64)
}
let harness = MainActor.assumeIsolated { Harness() }
MainActor.assumeIsolated { harness.start() }
Thread.detachNewThread {
    while let line = readLine() {
        let command = line.split(separator: " ")
        DispatchQueue.main.async { MainActor.assumeIsolated { harness.run(command) } }
    }
    DispatchQueue.main.async { MainActor.assumeIsolated { harness.restoreAndExit("end of input") } }
}
say("READY")
RunLoop.main.run()
