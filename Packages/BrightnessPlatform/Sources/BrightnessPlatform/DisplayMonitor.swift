import AppKit
import BrightnessCore

/// Reports display changes, and when dimming must stop because nobody is looking at this session.
///
/// A display added, removed or reconfigured, or a wake from sleep, is reported once things have
/// been quiet for `settleDelay`, because macOS sends a burst of notifications for one change and
/// may reset every display's curve partway through. Sleep, screen lock and switching to another
/// user suspend dimming straight away. Waking from sleep ends that suspension only together with
/// the settled display change, so dimming comes back after macOS has finished resetting the curves.
@MainActor public final class DisplayMonitor {
    /// How long after the last display notification the change is reported.
    public static let settleDelay = Duration.milliseconds(500)

    private enum SuspendReason {
        case asleep, locked, otherUserActive
    }

    private let onDisplaysChanged: @MainActor ([DisplayID]) -> Void
    private let onSuspendedChanged: @MainActor (Bool) -> Void
    private var reasons: Set<SuspendReason> = []
    private var settling: Task<Void, Never>?

    /// Whether the change waiting to settle includes a wake, so a later notification in the same
    /// burst doesn't lose it.
    private var settlingAfterWake = false
    private var observers: [(center: NotificationCenter, token: any NSObjectProtocol)] = []

    /// - Parameters:
    ///   - onDisplaysChanged: the displays changed or the Mac woke; called with the active displays.
    ///   - onSuspendedChanged: true when dimming must stop (asleep, locked, another user active), and
    ///     false once none of those holds any more.
    public init(
        onDisplaysChanged: @escaping @MainActor ([DisplayID]) -> Void,
        onSuspendedChanged: @escaping @MainActor (Bool) -> Void
    ) {
        self.onDisplaysChanged = onDisplaysChanged
        self.onSuspendedChanged = onSuspendedChanged
    }

    public func start() {
        guard observers.isEmpty else { return }
        let workspace = NSWorkspace.shared.notificationCenter
        let distributed = DistributedNotificationCenter.default()
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) {
            $0.displaysChanged()
        }
        observe(workspace, NSWorkspace.screensDidWakeNotification) { $0.displaysChanged() }
        observe(workspace, NSWorkspace.willSleepNotification) { $0.goingToSleep() }
        observe(workspace, NSWorkspace.didWakeNotification) { $0.displaysChanged(woke: true) }
        observe(workspace, NSWorkspace.sessionDidResignActiveNotification) { $0.set(.otherUserActive, true) }
        observe(workspace, NSWorkspace.sessionDidBecomeActiveNotification) { $0.set(.otherUserActive, false) }
        observe(distributed, Notification.Name("com.apple.screenIsLocked")) { $0.set(.locked, true) }
        observe(distributed, Notification.Name("com.apple.screenIsUnlocked")) { $0.set(.locked, false) }
    }

    public func stop() {
        for (center, token) in observers { center.removeObserver(token) }
        observers = []
        settling?.cancel()
        settling = nil
        settlingAfterWake = false
    }

    private func observe(
        _ center: NotificationCenter, _ name: Notification.Name, _ handle: @escaping @MainActor (DisplayMonitor) -> Void
    ) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                if let self { handle(self) }
            }
        }
        observers.append((center, token))
    }

    /// Reports the change once `settleDelay` passes with no further display notification.
    /// - Parameter woke: the Mac woke from sleep, which stops suspending once the change is reported.
    private func displaysChanged(woke: Bool = false) {
        settling?.cancel()
        if woke { settlingAfterWake = true }
        settling = Task { [weak self] in
            guard (try? await Task.sleep(for: Self.settleDelay)) != nil, let self else { return }
            // Read when the change is reported, so a sleep since the wake keeps dimming suspended.
            let woke = settlingAfterWake
            settlingAfterWake = false
            onDisplaysChanged(Displays.active)
            if woke { set(.asleep, false) }
        }
    }

    /// A wake still settling no longer counts: the Mac is going back to sleep.
    private func goingToSleep() {
        settlingAfterWake = false
        set(.asleep, true)
    }

    private func set(_ reason: SuspendReason, _ holds: Bool) {
        let wasSuspended = !reasons.isEmpty
        if holds { reasons.insert(reason) } else { reasons.remove(reason) }
        if reasons.isEmpty == wasSuspended { onSuspendedChanged(!reasons.isEmpty) }
    }
}
