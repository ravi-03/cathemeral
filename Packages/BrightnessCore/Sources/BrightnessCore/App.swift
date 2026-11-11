/// Identifies an app: its bundle ID, or its executable path if it has none.
///
/// Web apps installed to the Dock and beta or alternate builds have their own bundle IDs, so each
/// counts as a separate app.
public struct AppID: Hashable, Sendable, CustomStringConvertible {
    /// The bundle ID or executable path.
    public let rawValue: String
    private let isExecutablePath: Bool

    public init(bundleID: String) {
        self.init(rawValue: bundleID, isExecutablePath: false)
    }

    private init(rawValue: String, isExecutablePath: Bool) {
        self.rawValue = rawValue
        self.isExecutablePath = isExecutablePath
    }

    /// The bundle ID if there is one, otherwise the executable path, otherwise nil. Empty strings
    /// count as missing.
    public init?(bundleID: String?, executablePath: String?) {
        if let bundleID, !bundleID.isEmpty {
            self.init(bundleID: bundleID)
        } else if let executablePath, !executablePath.isEmpty {
            self.init(rawValue: executablePath, isExecutablePath: true)
        } else {
            return nil
        }
    }

    /// The bundle ID, or nil if the app is identified by its executable path.
    public var bundleID: String? { isExecutablePath ? nil : rawValue }

    /// The executable path, or nil if the app is identified by its bundle ID.
    public var executablePath: String? { isExecutablePath ? rawValue : nil }

    /// The executable's file name, or nil if the app is identified by its bundle ID.
    public var fileName: String? {
        executablePath?.split(separator: "/").last.map(String.init)
    }

    public var description: String { rawValue }
}

/// An app as Cathemeral shows it: its identity and the name to display.
public struct App: Hashable, Sendable {
    public let id: AppID
    public let name: String

    public init(id: AppID, name: String) {
        self.id = id
        self.name = name
    }
}

/// A running app with windows on screen, for the popover's list of other open windows.
public struct OpenApp: Hashable, Sendable {
    public let app: App
    /// How many of its windows are on screen.
    public let windowCount: Int

    public init(app: App, windowCount: Int) {
        self.app = app
        self.windowCount = windowCount
    }
}

/// An app with its own app setting, for the Settings window's Apps list.
public struct SavedApp: Hashable, Sendable {
    public let id: AppID
    /// The installed app's name. An app without a bundle ID shows by its file name.
    public let name: String
    public let level: Level
    /// False once the app is no longer on this Mac, so the list can grey it out.
    public let isInstalled: Bool

    public init(id: AppID, name: String, level: Level, isInstalled: Bool) {
        self.id = id
        self.name = name
        self.level = level
        self.isInstalled = isInstalled
    }
}
