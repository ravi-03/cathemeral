// Runs the real DimmingEngine, GammaController and ActivationMonitor, like the app does but
// with no UI, and takes commands on stdin so a script can drive it:
//
//   set <bundle-id> <fraction>   save an app setting (live if the app owns a display)
//   activate <bundle-id>         report an activation directly, as if that app came to the front
//                                on the built-in display (use for ignored apps like Spotlight,
//                                which `open` can't bring forward)
//   displays-changed             report a display change, as after plugging in a monitor or waking
//   suspend                      suspend dimming, as when the screen locks
//   unsuspend                    stop suspending, as when the screen unlocks (fades back)
//   quit                         restore gamma and exit
//
// It prints `READY` once listening, then one line per event. Gamma is restored on `quit`, on
// end of input, and on SIGTERM, SIGINT and SIGHUP. If it dies any other way, macOS resets its
// gamma when it exits (docs/platform/gamma.md).
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
    private var signalSources: [any DispatchSourceSignal] = []
    private lazy var activations = ActivationMonitor(
        onActivating: { [unowned self] app, display in engine.appActivating(app, on: display) },
        onActivation: { [unowned self] app, display in report(app, on: display) }
    )

    func start() {
        for terminationSignal in [SIGTERM, SIGINT, SIGHUP] {
            signal(terminationSignal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: terminationSignal, queue: .main)
            source.setEventHandler { [unowned self] in
                MainActor.assumeIsolated { restoreAndExit("signal \(terminationSignal)") }
            }
            source.resume()
            signalSources.append(source)
        }
        activations.start()
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
