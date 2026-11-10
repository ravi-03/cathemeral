import Observation

/// Works out which app owns each display and which level each display should show, and hands
/// those levels to the backend.
@MainActor @Observable public final class DimmingEngine {
    @ObservationIgnored private let backend: BrightnessBackend
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let clock: DimmingClock
    @ObservationIgnored private let ignoredApps: Set<AppID>
    @ObservationIgnored private var pendingSave: (any ScheduledAction)?

    /// How long a change caused by switching apps fades over. Settings changes, such as a slider
    /// drag, apply straight away.
    public static let switchRamp = Duration.milliseconds(150)

    /// How long the engine waits after the last change before saving, so dragging a slider
    /// writes the file once.
    public static let saveDelay = Duration.milliseconds(300)

    private var owners: [DisplayID: App] = [:]

    /// The level last handed to the backend for each display.
    @ObservationIgnored private var shown: [DisplayID: Level] = [:]
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

    /// macOS has started bringing `app` to the front, most likely on `display`, but its window may
    /// not be showing there yet. Follow with `appActivated` once it is.
    ///
    /// If the app's level is dimmer than the display shows now, the display dims straight away;
    /// a brighter level waits for `appActivated`. Either way nothing is ever shown brighter than its
    /// own level: dimming early only darkens the old app's window for a moment, while brightening
    /// early would flash it bright. An ignored app changes nothing.
    public func appActivating(_ app: App, on display: DisplayID) {
        guard !ignoredApps.contains(app.id) else { return }
        let level = level(for: app.id)
        if level < shown[display, default: .full] {
            show(level, on: display, over: Self.switchRamp)
        }
    }

    /// `app` is in front with its key window on `display`. It becomes the display owner.
    /// An ignored app changes nothing.
    public func appActivated(_ app: App, on display: DisplayID) {
        guard !ignoredApps.contains(app.id) else { return }
        owners[display] = app
        show(level(for: app.id), on: display, over: Self.switchRamp)
        // A display dimmed early for this app may not be where its window ended up.
        for (other, level) in shown where other != display {
            let target = owners[other].map { self.level(for: $0.id) } ?? .full
            if level != target { show(target, on: other, over: Self.switchRamp) }
        }
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

    private func show(_ level: Level, on display: DisplayID, over ramp: Duration) {
        shown[display] = level
        backend.apply(level, to: display, over: ramp)
    }

    /// Shows each owner's new level straight away, and saves the settings once the save delay passes with no
    /// further change.
    private func settingsChanged() {
        // Only displays whose level changed, so a display still fading after a switch isn't cut short.
        for (display, owner) in owners where shown[display] != level(for: owner.id) {
            show(level(for: owner.id), on: display, over: .zero)
        }
        pendingSave?.cancel()
        pendingSave = clock.schedule(after: Self.saveDelay) { [weak self] in
            self?.savePendingChanges()
        }
    }
}
