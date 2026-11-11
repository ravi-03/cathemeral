import AppKit
import BrightnessCore

/// Finds saved apps on this Mac, for the Settings window's Apps list. App settings are saved without
/// names or icons, so both come from here.
///
/// Each app is looked up once and remembered until `forget()`, since Launch Services lookups are too
/// slow to repeat on every redraw.
@MainActor public final class InstalledApps {
    private struct Installed {
        let name: String
        let icon: NSImage
    }

    /// Every app looked up so far, nil for one that isn't installed.
    private var cache: [AppID: Installed?] = [:]

    public init() {}

    /// The app's name, or nil if it isn't installed.
    public func name(of app: AppID) -> String? {
        lookUp(app)?.name
    }

    /// The app's icon, or nil if it isn't installed.
    public func icon(of app: AppID) -> NSImage? {
        lookUp(app)?.icon
    }

    /// Looks every app up again next time, to catch apps installed or removed since.
    public func forget() {
        cache = [:]
    }

    private func lookUp(_ app: AppID) -> Installed? {
        if let cached = cache[app] { return cached }
        let result: Installed?
        if let bundleID = app.bundleID {
            result = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID).map {
                Installed(name: Self.appName(at: $0), icon: NSWorkspace.shared.icon(forFile: $0.path))
            }
        } else if let path = app.executablePath, let fileName = app.fileName,
            FileManager.default.isExecutableFile(atPath: path)
        {
            result = Installed(name: fileName, icon: NSWorkspace.shared.icon(forFile: path))
        } else {
            result = nil
        }
        cache[app] = result
        return result
    }

    /// The name Finder shows, without ".app" even when Finder is set to show every extension.
    private static func appName(at url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }
}
