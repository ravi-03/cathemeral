import AppKit
import BrightnessCore

/// Lists the running apps with windows on screen and how many each has, for the popover's list of
/// other open windows: once on `start`, then every 2 seconds until `stop`. Call `start` when the
/// popover opens and `stop` when it closes, so nothing polls while it's closed.
///
/// Counts the same windows `FrontWindowTracker` reads: on-screen layer-0 windows, which needs no
/// permission. Hidden and quitting apps are left out.
@MainActor public final class WindowInventory {
    /// How often the window list is read while the popover is open.
    public static let interval = Duration.seconds(2)

    private let onChange: @MainActor ([OpenApp]) -> Void
    private var polling: Task<Void, Never>?

    /// - Parameter onChange: the apps with windows on screen, front to back, every 2 seconds.
    public init(onChange: @escaping @MainActor ([OpenApp]) -> Void) {
        self.onChange = onChange
    }

    /// Starts polling, reporting the current list straight away.
    public func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            repeat {
                guard let self else { return }
                onChange(Self.openApps())
            } while (try? await Task.sleep(for: Self.interval)) != nil
        }
    }

    public func stop() {
        polling?.cancel()
        polling = nil
    }

    /// The apps with windows on screen, front to back, with their window counts. Processes sharing
    /// an app ID count as one app.
    static func openApps() -> [OpenApp] {
        // Keyed by app ID, not `App`, so processes with one ID but different names still make one row.
        var order: [App] = []
        var counts: [AppID: Int] = [:]
        var appForPID: [pid_t: App?] = [:]
        for window in Displays.normalWindows() {
            let app = appForPID[window.pid] ?? Displays.visibleApp(window.pid)
            appForPID[window.pid] = app
            guard let app else { continue }
            if counts[app.id] == nil { order.append(app) }
            counts[app.id, default: 0] += 1
        }
        return order.map { OpenApp(app: $0, windowCount: counts[$0.id, default: 0]) }
    }
}
