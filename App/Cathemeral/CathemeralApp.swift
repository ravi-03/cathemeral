import BrightnessCore
import BrightnessPlatform
import SwiftUI

@main
struct CathemeralApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            PopoverView(engine: appDelegate.engine)
        } label: {
            Image(systemName: "sun.max")
        }
        .menuBarExtraStyle(.window)
    }
}

/// Wires the macOS signals into the engine, and on the way out saves settings and restores gamma.
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let engine = DimmingEngine(
        backend: GammaController(),
        store: FileSettingsStore(),
        clock: SystemClock(),
        selfID: AppID(bundleID: Bundle.main.bundleIdentifier ?? "io.github.ravi-03.cathemeral"),
        displays: Displays.active
    )

    private lazy var activations = ActivationMonitor(
        onActivating: { [engine] app, display in engine.appActivating(app, on: display) },
        onActivation: { [engine] app, display in engine.appActivated(app, on: display) },
        onLeft: { [engine] app, visibleApps in engine.appLeft(app, visibleApps: visibleApps) }
    )

    private lazy var windowTracker = FrontWindowTracker { [engine] visibleApps in
        engine.visibleAppsChanged(visibleApps)
    }

    private lazy var displayMonitor = DisplayMonitor(
        onDisplaysChanged: { [engine] online in engine.displaysChanged(to: online) },
        onSuspendedChanged: { [engine] suspended in engine.setSuspended(suspended) }
    )

    /// Kept alive so termination signals keep being handled.
    private var signalSources: [any DispatchSourceSignal] = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        restoreOnTerminationSignals()
        displayMonitor.start()
        activations.start()
        trackWindowsWhileNeeded()
    }

    /// Runs the window tracker only while something could be dimmed, and keeps it that way as
    /// settings change.
    private func trackWindowsWhileNeeded() {
        let needed = withObservationTracking {
            engine.needsWindowTracking
        } onChange: {
            // Called before the change lands, so look again once it has.
            Task { @MainActor [weak self] in self?.trackWindowsWhileNeeded() }
        }
        if needed { windowTracker.start() } else { windowTracker.stop() }
    }

    /// Termination signals skip `applicationWillTerminate`, so restore here too before exiting.
    private func restoreOnTerminationSignals() {
        for terminationSignal in [SIGTERM, SIGINT, SIGHUP] {
            signal(terminationSignal, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: terminationSignal, queue: .main)
            source.setEventHandler { [engine] in
                MainActor.assumeIsolated {
                    engine.restore()
                    engine.savePendingChanges()
                }
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }

    /// Every normal quit (the Quit button, Cmd-Q, logout) passes through here.
    func applicationWillTerminate(_ notification: Notification) {
        activations.stop()
        windowTracker.stop()
        displayMonitor.stop()
        engine.restore()
        engine.savePendingChanges()
    }
}
