import AppKit
import BrightnessCore

/// Once a second, lists the apps visible on each display, topmost first, and reports the list.
/// This is how ownership follows a window minimised, closed or dragged to
/// another display, or a Space switch, none of which macOS announces.
///
/// Reads only layer-0 windows from the on-screen window list, which needs no permission. Each
/// window counts for the display it overlaps most.
@MainActor public final class FrontWindowTracker {
    /// How often the window list is read.
    public static let interval = Duration.seconds(1)

    private let onChange: @MainActor ([DisplayID: [App]]) -> Void
    private var polling: Task<Void, Never>?

    /// - Parameter onChange: the apps visible on each display, topmost first, every second. A display
    ///   with no visible app is missing. Reported even when unchanged, so an app brought to the front
    ///   with no windows loses its display within a second.
    public init(onChange: @escaping @MainActor ([DisplayID: [App]]) -> Void) {
        self.onChange = onChange
    }

    public var isRunning: Bool { polling != nil }

    /// Starts polling, reporting the current list straight away.
    public func start() {
        guard polling == nil else { return }
        polling = Task { [weak self] in
            repeat {
                guard let self else { return }
                onChange(Displays.visibleApps())
            } while (try? await Task.sleep(for: Self.interval)) != nil
        }
    }

    public func stop() {
        polling?.cancel()
        polling = nil
    }
}
