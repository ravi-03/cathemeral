import BrightnessCore
import CoreGraphics
import Foundation

/// Finds displays.
public enum Displays {
    /// The display with the menu bar.
    public static var main: DisplayID { DisplayID(CGMainDisplayID()) }

    /// The built-in display, or the main display if there is no built-in one (a closed laptop or a
    /// desktop Mac).
    public static var builtIn: DisplayID {
        online.first { CGDisplayIsBuiltin($0.rawValue) != 0 } ?? main
    }

    public static var online: [DisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(DisplayID.init)
    }

    /// The display that the app's frontmost normal window overlaps most, or nil if it has no
    /// window on screen.
    static func holdingFrontmostWindow(of pid: pid_t) -> DisplayID? {
        normalWindows().first { $0.pid == pid }?.display
    }

    /// The display where the app's frontmost normal window is now the topmost normal window, or nil
    /// if WindowServer hasn't brought it there yet (or the app has no window on screen).
    ///
    /// Activation is reported before WindowServer reorders windows, often by 50 ms or more, so this
    /// tells when the app's window has actually reached the front.
    static func whereFrontmost(_ pid: pid_t) -> DisplayID? {
        let windows = normalWindows()
        guard let display = windows.first(where: { $0.pid == pid })?.display else { return nil }
        return windows.first { $0.display == display }?.pid == pid ? display : nil
    }

    /// On-screen normal (layer 0) windows, front to back, each with its owner and the display it
    /// overlaps most.
    private static func normalWindows() -> [(pid: pid_t, display: DisplayID)] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        let displays = online
        return windows.compactMap { window in
            guard
                (window[kCGWindowLayer as String] as? Int) == 0,
                let pid = window[kCGWindowOwnerPID as String] as? pid_t,
                let boundsInfo = window[kCGWindowBounds as String] as? NSDictionary,
                let bounds = CGRect(dictionaryRepresentation: boundsInfo),
                let display = displays.max(by: { overlap(bounds, $0) < overlap(bounds, $1) }),
                overlap(bounds, display) > 0
            else { return nil }
            return (pid, display)
        }
    }

    private static func overlap(_ bounds: CGRect, _ display: DisplayID) -> CGFloat {
        let shared = bounds.intersection(CGDisplayBounds(display.rawValue))
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
