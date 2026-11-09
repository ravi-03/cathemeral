import AppKit
import BrightnessCore

/// Reports each app brought to the front, with the display holding its frontmost window.
@MainActor public final class ActivationMonitor {
    private let onActivation: @MainActor (App, DisplayID) -> Void
    private var observer: (any NSObjectProtocol)?

    public init(onActivation: @escaping @MainActor (App, DisplayID) -> Void) {
        self.onActivation = onActivation
    }

    /// Starts reporting, beginning with the app that is in front right now.
    public func start() {
        guard observer == nil else { return }
        observer = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            // Only the PID crosses into the main actor; the notification isn't Sendable.
            let running = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            guard let pid = running?.processIdentifier else { return }
            MainActor.assumeIsolated {
                if let running = NSRunningApplication(processIdentifier: pid) { self?.report(running) }
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication { report(frontmost) }
    }

    public func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
    }

    private func report(_ running: NSRunningApplication) {
        guard
            let id = AppID(bundleID: running.bundleIdentifier, executablePath: running.executableURL?.path)
        else { return }
        let name = running.localizedName ?? running.executableURL?.lastPathComponent ?? id.rawValue
        let display = Displays.holdingFrontmostWindow(of: running.processIdentifier) ?? Displays.main
        onActivation(App(id: id, name: name), display)
    }
}
