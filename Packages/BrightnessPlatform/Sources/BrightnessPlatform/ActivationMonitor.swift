import AppKit
import BrightnessCore

/// Reports each app brought to the front, with the display holding its frontmost window.
///
/// macOS announces an activation before WindowServer brings the app's window forward, often by
/// 50 ms or more. So each switch is reported twice: `onActivating` as soon as macOS announces it,
/// and `onActivation` once the app's window is the topmost window on its display, or after
/// `windowWaitLimit` for an app whose window never comes forward (such as one with no windows).
/// The engine dims on the first and brightens on the second, so neither app flashes bright.
@MainActor public final class ActivationMonitor {
    /// How often to check whether the activated app's window has reached the front.
    private static let windowPollInterval = Duration.milliseconds(4)

    /// How long to wait for the window before reporting anyway.
    private static let windowWaitLimit = Duration.milliseconds(250)

    private let onActivating: @MainActor (App, DisplayID) -> Void
    private let onActivation: @MainActor (App, DisplayID) -> Void
    private var observer: (any NSObjectProtocol)?

    /// Waits for the latest activation's window. A newer activation cancels it.
    private var windowWait: Task<Void, Never>?

    /// - Parameters:
    ///   - onActivating: macOS has announced the app is coming to the front, most likely on that
    ///     display. Its window may not be showing yet.
    ///   - onActivation: the app's window is in front on that display.
    public init(
        onActivating: @escaping @MainActor (App, DisplayID) -> Void,
        onActivation: @escaping @MainActor (App, DisplayID) -> Void
    ) {
        self.onActivating = onActivating
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
                if let running = NSRunningApplication(processIdentifier: pid) { self?.reportOnceInFront(running) }
            }
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication, let app = Self.app(frontmost) {
            onActivation(app, Self.display(of: frontmost))
        }
    }

    public func stop() {
        if let observer { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observer = nil
        windowWait?.cancel()
        windowWait = nil
    }

    /// Reports `running` as activating now, then as activated once its window is topmost on a
    /// display (checking every `windowPollInterval`), or after `windowWaitLimit` at the latest.
    private func reportOnceInFront(_ running: NSRunningApplication) {
        windowWait?.cancel()
        guard let app = Self.app(running) else { return }
        let pid = running.processIdentifier
        onActivating(app, Self.display(of: running))
        windowWait = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.windowWaitLimit
            var display = Displays.whereFrontmost(pid)
            while display == nil, ContinuousClock.now < deadline {
                try? await Task.sleep(for: Self.windowPollInterval)
                guard !Task.isCancelled else { return }
                display = Displays.whereFrontmost(pid)
            }
            guard !Task.isCancelled else { return }  // Replaced before this task first ran.
            self?.onActivation(app, display ?? Self.display(of: running))
        }
    }

    private static func app(_ running: NSRunningApplication) -> App? {
        guard
            let id = AppID(bundleID: running.bundleIdentifier, executablePath: running.executableURL?.path)
        else { return nil }
        let name = running.localizedName ?? running.executableURL?.lastPathComponent ?? id.rawValue
        return App(id: id, name: name)
    }

    /// The display holding the app's frontmost window, or the main display if it has none.
    private static func display(of running: NSRunningApplication) -> DisplayID {
        Displays.holdingFrontmostWindow(of: running.processIdentifier) ?? Displays.main
    }
}
