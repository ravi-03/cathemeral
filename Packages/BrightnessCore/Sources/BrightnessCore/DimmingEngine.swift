import Observation

/// Works out which app owns each display and which level each display should show, and hands
/// those levels to the backend.
@MainActor @Observable public final class DimmingEngine {
    @ObservationIgnored private let backend: BrightnessBackend
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let clock: DimmingClock
    @ObservationIgnored private let ignoredApps: Set<AppID>
    @ObservationIgnored private var pendingSave: (any ScheduledAction)?

    /// How long the engine waits after the last change before saving, so dragging a slider
    /// writes the file once.
    public static let saveDelay = Duration.milliseconds(300)

    private var owners: [DisplayID: App] = [:]
    private var settings: Settings

    /// - Parameter selfID: Cathemeral's own app ID. Cathemeral is an ignored app.
    public init(backend: BrightnessBackend, store: SettingsStore, clock: DimmingClock, selfID: AppID) {
        self.backend = backend
        self.store = store
        self.clock = clock
        ignoredApps = IgnoredApps.system.union([selfID])
        settings = store.load()
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
        settings.appSettings[app] = level
        settingsChanged()
    }

    /// Removes the app's app setting, so it follows the default level from now on.
    public func useDefault(for app: AppID) {
        guard settings.appSettings.removeValue(forKey: app) != nil else { return }
        settingsChanged()
    }

    /// Whether the app has its own app setting rather than using the default level.
    public func hasAppSetting(for app: AppID) -> Bool {
        settings.appSettings[app] != nil
    }

    /// The level for any app without its own app setting.
    public var defaultLevel: Level { settings.defaultLevel }

    /// Changes the default level. Every display owned by an app without an app setting shows the
    /// new level straight away.
    public func setDefaultLevel(_ level: Level) {
        settings.defaultLevel = level
        settingsChanged()
    }

    /// The app's own app setting, or the default level if it has none.
    public func level(for app: AppID) -> Level {
        settings.appSettings[app] ?? settings.defaultLevel
    }

    /// Saves any change still waiting out the save delay. Call before quitting.
    public func savePendingChanges() {
        guard let pendingSave else { return }
        pendingSave.cancel()
        self.pendingSave = nil
        store.save(settings)
    }

    /// Puts every display back to its original curve. Call before quitting.
    public func restore() {
        backend.restore()
    }

    /// Shows each owner's current level, and saves the settings once the save delay passes with no
    /// further change.
    private func settingsChanged() {
        for (display, owner) in owners {
            backend.apply(level(for: owner.id), to: display)
        }
        pendingSave?.cancel()
        pendingSave = clock.schedule(after: Self.saveDelay) { [weak self] in
            self?.savePendingChanges()
        }
    }
}
