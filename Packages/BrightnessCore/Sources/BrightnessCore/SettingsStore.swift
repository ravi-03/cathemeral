import Observation

/// Holds app settings and the default level.
@MainActor public protocol SettingsStore: AnyObject {
    /// The level the user saved for `app`, or nil if it uses the default level.
    func appSetting(for app: AppID) -> Level?

    func setAppSetting(_ level: Level, for app: AppID)

    /// The level for any app without its own app setting.
    var defaultLevel: Level { get set }
}

/// Keeps settings in memory only. They are lost on quit.
///
/// Observable, so views that read a level through the engine update when it changes.
@MainActor @Observable public final class InMemorySettingsStore: SettingsStore {
    private var appSettings: [AppID: Level] = [:]
    public var defaultLevel: Level

    public init(defaultLevel: Level = .full) {
        self.defaultLevel = defaultLevel
    }

    public func appSetting(for app: AppID) -> Level? {
        appSettings[app]
    }

    public func setAppSetting(_ level: Level, for app: AppID) {
        appSettings[app] = level
    }
}
