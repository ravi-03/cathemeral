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
            StatusIcon(engine: appDelegate.engine)
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

/// The menu bar icon, with a dot while any display is paused.
struct StatusIcon: View {
    let engine: DimmingEngine

    var body: some View {
        Image(nsImage: Self.image(withDot: engine.hasPausedDisplay))
    }

    /// The menu bar shows only a label's image, not overlays, so the dot is drawn into the image.
    /// A template image, so it follows the menu bar's colour.
    private static func image(withDot: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        guard
            let sun = NSImage(systemSymbolName: "sun.max", accessibilityDescription: "Cathemeral")?
                .withSymbolConfiguration(configuration)
        else { return NSImage() }
        guard withDot else { return sun }
        let dot: CGFloat = 6
        let image = NSImage(size: sun.size, flipped: false) { bounds in
            sun.draw(in: bounds)
            // Clear a ring around the dot so it stands apart from the rays.
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(
                ovalIn: NSRect(x: bounds.maxX - dot - 2, y: bounds.maxY - dot - 2, width: dot + 2, height: dot + 2)
            )
            .fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: bounds.maxX - dot - 1, y: bounds.maxY - dot - 1, width: dot, height: dot))
                .fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Cathemeral: a display is paused"
        return image
    }
}
