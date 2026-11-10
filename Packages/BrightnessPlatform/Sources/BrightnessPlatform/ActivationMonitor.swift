import AppKit
import BrightnessCore

/// Reports each app brought to the front, with the display holding its frontmost window.
///
/// macOS announces an activation before WindowServer brings the app's window forward, often by
/// 50 ms or more. So each switch is reported twice: `onActivating` as soon as macOS announces it,
/// and `onActivation` once the app's window is the topmost window on its display, or after
/// `windowWaitLimit` for an app whose window never comes forward (such as one with no windows).
/// The engine dims on the first and brightens on the second, so neither app flashes bright.
///
/// It also reports each app hidden or quit, once its windows have left the screen (or after
/// `windowWaitLimit`), so the display it leaves never brightens while its window still shows.
@MainActor public final class ActivationMonitor {
    /// How often to check whether the activated app's window has reached the front.
    private static let windowPollInterval = Duration.milliseconds(4)

    /// How long to wait for the window before reporting anyway.
    private static let windowWaitLimit = Duration.milliseconds(250)

    private let onActivating: @MainActor (App, DisplayID) -> Void
    private let onActivation: @MainActor (App, DisplayID) -> Void
    private let onLeft: @MainActor (AppID, [DisplayID: [App]]) -> Void
    private var observers: [any NSObjectProtocol] = []

    /// The app whose window `windowWait` is waiting for.
    private var waitingFor: AppID?

    /// Waits for the windows of apps just hidden or quit to leave the screen.
    private var leaveWaits: [pid_t: Task<Void, Never>] = [:]

    /// Waits for the latest activation's window. A newer activation cancels it.
    private var windowWait: Task<Void, Never>?

    /// - Parameters:
    ///   - onActivating: macOS has announced the app is coming to the front, most likely on that
    ///     display. Its window may not be showing yet.
    ///   - onActivation: the app's window is in front on that display.
    ///   - onLeft: the app was hidden or quit and its windows are gone; with the apps now visible on
    ///     each display, topmost first.
    public init(
        onActivating: @escaping @MainActor (App, DisplayID) -> Void,
        onActivation: @escaping @MainActor (App, DisplayID) -> Void,
        onLeft: @escaping @MainActor (AppID, [DisplayID: [App]]) -> Void
    ) {
        self.onActivating = onActivating
        self.onActivation = onActivation
        self.onLeft = onLeft
    }

    /// Starts reporting, beginning with the app that is in front right now.
    public func start() {
        guard observers.isEmpty else { return }
        let center = NSWorkspace.shared.notificationCenter
        observers.append(
            center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) {
                [weak self] notification in
                // Only the PID crosses into the main actor; the notification isn't Sendable.
                guard let pid = Self.runningApp(in: notification)?.processIdentifier else { return }
                MainActor.assumeIsolated {
                    if let running = NSRunningApplication(processIdentifier: pid) { self?.reportOnceInFront(running) }
                }
            })
        for name in [NSWorkspace.didHideApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(
                center.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                    guard let running = Self.runningApp(in: notification), let app = App(running: running) else {
                        return
                    }
                    let pid = running.processIdentifier
                    MainActor.assumeIsolated { self?.reportLeft(app.id, pid: pid) }
                })
        }
        if let frontmost = NSWorkspace.shared.frontmostApplication, let app = App(running: frontmost) {
            onActivation(app, Self.display(of: frontmost))
        }
    }

    public func stop() {
        for observer in observers { NSWorkspace.shared.notificationCenter.removeObserver(observer) }
        observers = []
        windowWait?.cancel()
        windowWait = nil
        waitingFor = nil
        for wait in leaveWaits.values { wait.cancel() }
        leaveWaits = [:]
    }

    /// Reports `app` as left once its windows are off screen, checking every `windowPollInterval`,
    /// or after `windowWaitLimit` at the latest. An app that leaves while its activation waits for
    /// its window is never reported as activated.
    private func reportLeft(_ app: AppID, pid: pid_t) {
        if waitingFor == app {
            windowWait?.cancel()
            waitingFor = nil
        }
        leaveWaits[pid]?.cancel()
        leaveWaits[pid] = Task { [weak self] in
            let deadline = ContinuousClock.now + Self.windowWaitLimit
            while Displays.holdingFrontmostWindow(of: pid) != nil, ContinuousClock.now < deadline {
                try? await Task.sleep(for: Self.windowPollInterval)
                guard !Task.isCancelled else { return }
            }
            guard !Task.isCancelled, let self else { return }
            leaveWaits[pid] = nil
            onLeft(app, Displays.visibleApps())
        }
    }

    private nonisolated static func runningApp(in notification: Notification) -> NSRunningApplication? {
        notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
    }

    /// Reports `running` as activating now, then as activated once its window is topmost on a
    /// display (checking every `windowPollInterval`), or after `windowWaitLimit` at the latest.
    private func reportOnceInFront(_ running: NSRunningApplication) {
        windowWait?.cancel()
        guard let app = App(running: running) else { return }
        let pid = running.processIdentifier
        waitingFor = app.id
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
            self?.waitingFor = nil
            self?.onActivation(app, display ?? Self.display(of: running))
        }
    }

    /// The display holding the app's frontmost window, or the main display if it has none.
    private static func display(of running: NSRunningApplication) -> DisplayID {
        Displays.holdingFrontmostWindow(of: running.processIdentifier) ?? Displays.main
    }
}

extension App {
    /// The app a running process belongs to, or nil if it has neither a bundle ID nor an executable.
    init?(running: NSRunningApplication) {
        guard
            let id = AppID(bundleID: running.bundleIdentifier, executablePath: running.executableURL?.path)
        else { return nil }
        self.init(id: id, name: running.localizedName ?? running.executableURL?.lastPathComponent ?? id.rawValue)
    }
}
