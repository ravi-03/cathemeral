import BrightnessCore
import BrightnessPlatform
import SwiftUI

@main
struct CathemeralApp: SwiftUI.App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    /// The menu bar icon and popover are AppKit's (`StatusItemController`), since a SwiftUI menu bar
    /// extra can't tell a right-click from a click. A scene is still required, and an empty Settings
    /// scene shows nothing.
    var body: some Scene {
        Settings { EmptyView() }
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

    private let loginItem = LoginItem()
    private lazy var settingsWindow = SettingsWindow(engine: engine, loginItem: loginItem)
    private var statusItem: StatusItemController?

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
        statusItem = StatusItemController(engine: engine, loginItem: loginItem) { [weak self] in
            self?.settingsWindow.show()
        }
    }

    /// Runs the window tracker only while something could be dimmed, and keeps it that way as
    /// settings change.
    private func trackWindowsWhileNeeded() {
        let needed = withObservationTracking {
            engine.needsWindowTracking
        } onChange: { [weak self] in
            // Called before the change lands, so look again once it has.
            Task { @MainActor in self?.trackWindowsWhileNeeded() }
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
