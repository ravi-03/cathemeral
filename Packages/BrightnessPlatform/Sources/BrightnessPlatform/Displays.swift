import AppKit
import BrightnessCore
import CoreGraphics

/// Finds displays.
public enum Displays {
    /// The display with the menu bar.
    public static var main: DisplayID { DisplayID(CGMainDisplayID()) }

    /// The built-in display, or the main display if there is no built-in one (a closed laptop or a
    /// desktop Mac).
    public static var builtIn: DisplayID {
        online.first(where: isBuiltIn) ?? main
    }

    /// "Built-in" for the built-in display, otherwise the monitor's name as macOS shows it.
    @MainActor public static func name(of display: DisplayID) -> String {
        if isBuiltIn(display) { return "Built-in" }
        return screen(showing: display)?.localizedName ?? "Display \(display.rawValue)"
    }

    /// The displays drawing right now, one per mirrored set. Leaves out asleep displays and the
    /// extra members of a mirrored set, which `online` includes.
    public static var active: [DisplayID] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        return ids.prefix(Int(count)).map(DisplayID.init)
    }

    /// The screen AppKit uses for `display`, or nil if it has none (asleep, or mirrored).
    @MainActor static func screen(showing display: DisplayID) -> NSScreen? {
        NSScreen.screens.first { $0.displayID == display }
    }

    private static func isBuiltIn(_ display: DisplayID) -> Bool {
        CGDisplayIsBuiltin(display.rawValue) != 0
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

    /// The apps with a normal window on screen, per display, topmost first. Each window counts for
    /// the display it overlaps most. Windows on other Spaces, minimised or closed aren't on screen.
    /// Hidden and quitting apps are left out, since their windows can stay listed for a moment.
    @MainActor public static func visibleApps() -> [DisplayID: [App]] {
        var visible: [DisplayID: [App]] = [:]
        var apps: [pid_t: App?] = [:]
        for window in normalWindows() {
            let app = apps[window.pid] ?? visibleApp(window.pid)
            apps[window.pid] = app
            guard let app, !visible[window.display, default: []].contains(app) else { continue }
            visible[window.display, default: []].append(app)
        }
        return visible
    }

    @MainActor private static func visibleApp(_ pid: pid_t) -> App? {
        guard let running = NSRunningApplication(processIdentifier: pid), !running.isHidden, !running.isTerminated
        else { return nil }
        return App(running: running)
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

extension NSScreen {
    /// The CoreGraphics display this screen shows.
    fileprivate var displayID: DisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { DisplayID($0.uint32Value) }
    }
}
