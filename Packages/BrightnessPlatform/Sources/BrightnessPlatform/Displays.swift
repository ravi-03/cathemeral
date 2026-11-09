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
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }
        // The list is ordered front to back. Layer 0 holds normal app windows.
        let frontmost = windows.first {
            ($0[kCGWindowOwnerPID as String] as? pid_t) == pid && ($0[kCGWindowLayer as String] as? Int) == 0
        }
        guard
            let boundsInfo = frontmost?[kCGWindowBounds as String] as? NSDictionary,
            let bounds = CGRect(dictionaryRepresentation: boundsInfo)
        else { return nil }
        return online.max { overlap(bounds, $0) < overlap(bounds, $1) }
    }

    private static func overlap(_ bounds: CGRect, _ display: DisplayID) -> CGFloat {
        let shared = bounds.intersection(CGDisplayBounds(display.rawValue))
        return shared.isNull ? 0 : shared.width * shared.height
    }
}
