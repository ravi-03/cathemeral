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
