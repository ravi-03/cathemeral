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

    /// Restores gamma on termination signals, and keeps the watchdog that restores it on a hang.
    private lazy var safetyNet = SafetyNet(
        watchdog: Bundle.main.bundleURL.appending(path: "Contents/MacOS/GammaWatchdog"),
        beforeExit: { [engine] in
            engine.restore()
            engine.savePendingChanges()
        },
        onRestoredFromOutside: { [engine] in engine.restoredFromOutside() }
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        safetyNet.start()
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

    /// Every normal quit (the Quit button, Cmd-Q, logout) passes through here.
    func applicationWillTerminate(_ notification: Notification) {
        activations.stop()
        windowTracker.stop()
        displayMonitor.stop()
        safetyNet.stop()
        engine.restore()
        engine.savePendingChanges()
    }
}
