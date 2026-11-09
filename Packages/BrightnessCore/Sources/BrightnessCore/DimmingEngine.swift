import Observation

/// Works out which app owns each display and which level each display should show, and hands
/// those levels to the backend.
@MainActor @Observable public final class DimmingEngine {
    @ObservationIgnored private let backend: BrightnessBackend
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let clock: DimmingClock
    @ObservationIgnored private let ignoredApps: Set<AppID>

    private var owners: [DisplayID: App] = [:]

    /// - Parameter selfID: Cathemeral's own app ID. Cathemeral is an ignored app.
    public init(backend: BrightnessBackend, store: SettingsStore, clock: DimmingClock, selfID: AppID) {
        self.backend = backend
        self.store = store
        self.clock = clock
        ignoredApps = IgnoredApps.system.union([selfID])
    }

    /// The display owner, or nil if the display is unowned.
    public func owner(of display: DisplayID) -> App? {
        owners[display]
    }

    /// `app` was brought to the front with its key window on `display`.
    /// An ignored app changes nothing.
    public func appActivated(_ app: App, on display: DisplayID) {
        guard !ignoredApps.contains(app.id) else { return }
        owners[display] = app
        backend.apply(level(for: app.id), to: display)
    }

    /// Saves `level` as the app's app setting. If the app owns a display, the display shows the new
    /// level straight away.
    public func setLevel(_ level: Level, for app: AppID) {
        store.setAppSetting(level, for: app)
        for (display, owner) in owners where owner.id == app {
            backend.apply(level, to: display)
        }
    }

    /// The app's own app setting, or the default level if it has none.
    public func level(for app: AppID) -> Level {
        store.appSetting(for: app) ?? store.defaultLevel
    }

    /// Puts every display back to its original curve. Call before quitting.
    public func restore() {
        backend.restore()
    }
}
