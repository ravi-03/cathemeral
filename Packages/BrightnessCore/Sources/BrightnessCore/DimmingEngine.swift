import Observation

/// Works out which app owns each display and which level each display should show, and hands
/// those levels to the backend.
@MainActor @Observable public final class DimmingEngine: BrightnessBackendDelegate {
    @ObservationIgnored private let backend: BrightnessBackend
    @ObservationIgnored private let store: SettingsStore
    @ObservationIgnored private let clock: DimmingClock
    @ObservationIgnored private let ignoredApps: Set<AppID>
    @ObservationIgnored private var pendingSave: (any ScheduledAction)?
    @ObservationIgnored private var lastSettingsApply: ContinuousClock.Instant?
    @ObservationIgnored private var pendingSettingsApply: (any ScheduledAction)?

    /// How long a change caused by switching apps fades over. Settings changes, such as a slider
    /// drag, apply straight away.
    public static let switchRamp = Duration.milliseconds(150)

    /// The shortest gap between two settings changes reaching the screen, so a slider drag writes at
    /// most 30 times a second. A change inside the gap waits for its end, and the last one always lands.
    public static let settingsApplyInterval = Duration.seconds(1) / 30

    /// How long the engine waits after the last change before saving, so dragging a slider
    /// writes the file once.
    public static let saveDelay = Duration.milliseconds(300)

    /// The online displays, in the order macOS lists them.
    public private(set) var displays: [DisplayID]

    private var owners: [DisplayID: App] = [:]

    /// Displays that get no level, and why. A display missing here is dimming.
    private var notDimming: [DisplayID: DisplayStatus] = [:]

    /// The level each display shows, or would show if the engine weren't suspended.
    @ObservationIgnored private var shown: [DisplayID: Level] = [:]

    /// While suspended, every display keeps its original curve and nothing is written.
    private var isSuspended = false

    /// Whether levels reach the screen: dimming is on and not suspended.
    private var isShowingLevels: Bool { settings.isEnabled && !isSuspended }

    /// The app reported by `appActivating` whose `appActivated` hasn't arrived yet. Displays may
    /// be dimmed early for it.
    @ObservationIgnored private var activating: AppID?
    private var settings: Settings

    /// - Parameters:
    ///   - selfID: Cathemeral's own app ID. Cathemeral is an ignored app.
    ///   - displays: the displays online at launch. Later changes arrive through `displaysChanged`.
    public init(
        backend: BrightnessBackend, store: SettingsStore, clock: DimmingClock, selfID: AppID,
        displays: [DisplayID] = []
    ) {
        self.backend = backend
        self.displays = displays
        self.store = store
        self.clock = clock
        ignoredApps = IgnoredApps.system.union([selfID])
        settings = store.load()
        backend.delegate = self
    }

    /// The display owner, or nil if the display is unowned.
    public func owner(of display: DisplayID) -> App? {
        owners[display]
    }

    /// Whether `display` takes levels, and if not, why.
    public func status(of display: DisplayID) -> DisplayStatus {
        notDimming[display] ?? .dimming
    }

    /// The apps in `open` not already shown on a display card, for the popover's list of other open
    /// windows, sorted by name. Leaves out the owner of each display that is dimming, and ignored
    /// apps. The owner of a paused or unsupported display stays in, since its card doesn't show it.
    public func otherOpenApps(_ open: [OpenApp]) -> [OpenApp] {
        let onCards = Set(owners.filter { status(of: $0.key) == .dimming }.values.map(\.id))
        return
            open
            .filter { !onCards.contains($0.app.id) && !ignoredApps.contains($0.app.id) }
            .sorted { $0.app.name.localizedStandardCompare($1.app.name) == .orderedAscending }
    }

    /// Whether dimming is off, or else whether any display is dimmed right now, for the status icon.
    /// A display counts as dimmed when it is dimming and its target is below 100%; a paused or
    /// unsupported display, or any display while suspended, doesn't.
    public var dimmingState: DimmingState {
        guard settings.isEnabled else { return .off }
        let anyDimmed =
            !isSuspended && owners.keys.contains { status(of: $0) == .dimming && target(for: $0) < .full }
        return anyDimmed ? .dimmed : .nothingDimmed
    }

    /// Whether any display is paused, for the dot on the status icon.
    public var hasPausedDisplay: Bool { notDimming.values.contains(.paused) }

    /// Another app has taken over `display`'s colours, so it gets no more levels until `resume`.
    /// Other displays carry on.
    public func displayPaused(_ display: DisplayID) {
        stopShowing(on: display, because: .paused)
    }

    /// Levels don't take on `display`, so it gets none until the displays next change.
    public func displayUnsupported(_ display: DisplayID) {
        stopShowing(on: display, because: .unsupported)
    }

    /// The user chose Resume on a paused display. The backend captures the display's current curve,
    /// with the other app's colours, as its original, and the display fades to its owner's level on
    /// top of it. If the other app takes over again, the display pauses again.
    public func resume(_ display: DisplayID) {
        guard notDimming[display] == .paused else { return }
        notDimming[display] = nil
        backend.resume(display)
        show(target(for: display), on: display, over: Self.switchRamp)
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
        activating = app.id
        let level = level(for: app.id)
        if level < shown[display, default: .full] {
            show(level, on: display, over: Self.switchRamp)
        }
    }

    /// `app` is in front with its key window on `display`. It becomes the display owner.
    /// An ignored app changes nothing.
    public func appActivated(_ app: App, on display: DisplayID) {
        guard !ignoredApps.contains(app.id) else { return }
        activating = nil
        owners[display] = app
        show(level(for: app.id), on: display, over: Self.switchRamp)
        // A display dimmed early for this app may not be where its window ended up.
        showEveryTargetNotShown()
    }

    /// The apps with a visible window on each display, topmost first, reported every second. A
    /// display missing from `visibleApps` has none. Each report also has the backend check its
    /// tables, unless suspended.
    ///
    /// An owner with no visible window left on its display loses it, and each display without an
    /// owner passes to its topmost visible app that isn't an ignored app, or stays unowned if there
    /// is none.
    public func visibleAppsChanged(_ visibleApps: [DisplayID: [App]]) {
        var handedOver: Set<DisplayID> = []
        for (display, owner) in owners where !visibleApps[display, default: []].contains(owner) {
            owners[display] = nil
            handedOver.insert(display)
        }
        for (display, apps) in visibleApps where owners[display] == nil {
            guard let topmost = apps.first(where: { !ignoredApps.contains($0.id) }) else { continue }
            owners[display] = topmost
            handedOver.insert(display)
        }
        for display in handedOver where target(for: display) != shown[display, default: .full] {
            // Mid-switch, a display may be dimmed early for the app coming to the front. Brightening it
            // now would flash the old window bright; `appActivated` sets it right once the switch ends.
            if activating != nil, target(for: display) > shown[display, default: .full] { continue }
            show(target(for: display), on: display, over: Self.switchRamp)
        }
        // This is the 1 Hz tick: another app's write, or a reset when a gamma writer exits, is
        // announced by nothing, so the backend reads its tables back.
        if isShowingLevels { backend.checkTables() }
    }

    /// `app` was hidden or quit. Every display it owned passes straight away to its topmost visible
    /// app, or becomes unowned. The app is left out of `visibleApps` even if it's listed there.
    public func appLeft(_ app: AppID, visibleApps: [DisplayID: [App]]) {
        if activating == app {
            // Its switch will never finish, so undo any display dimmed early for it.
            activating = nil
            showEveryTargetNotShown()
        }
        visibleAppsChanged(visibleApps.mapValues { $0.filter { $0.id != app } })
    }

    /// Displays were added, removed or reconfigured, or the Mac woke up. macOS may have reset every
    /// display's curve, so the backend restores and re-captures each original, and every owned
    /// display is shown at its owner's level again, straight away rather than fading. A paused
    /// display stays paused; an unsupported one is tried again.
    public func displaysChanged(to online: [DisplayID]) {
        displays = online
        owners = owners.filter { online.contains($0.key) }
        // A paused display stays paused. A display change may have brought a different display, or
        // a different mode, under an unsupported display's ID, so it is tried again.
        notDimming = notDimming.filter { online.contains($0.key) && $0.value == .paused }
        backend.restore()
        showEveryOwnersLevel(over: .zero)
    }

    /// While the screen is locked, another user is active or the Mac is asleep, every display goes
    /// back to its original curve, so the login window is never dimmed. Ownership and settings
    /// keep changing as usual. When the engine stops being suspended, every owned display fades
    /// from its original curve back to its owner's level.
    public func setSuspended(_ suspended: Bool) {
        guard suspended != isSuspended else { return }
        let wasShowing = isShowingLevels
        isSuspended = suspended
        guard isShowingLevels != wasShowing else { return }
        if isShowingLevels {
            showEveryOwnersLevel(over: Self.switchRamp)
        } else {
            // The screen is locked or asleep, so nobody sees this jump.
            backend.restore()
        }
    }

    /// The master switch.
    public var isEnabled: Bool { settings.isEnabled }

    /// Turns all dimming off or back on, and saves the choice. Turned off, every dimmed display fades
    /// to 100%, which is its original curve, and nothing more is written. Activations still change
    /// ownership and settings still change, but windows aren't tracked (`needsWindowTracking`).
    /// Turned back on, every owned display fades to its owner's level; the window tracker, started
    /// again, hands over any display whose owner left meanwhile within a second.
    public func setEnabled(_ enabled: Bool) {
        guard enabled != settings.isEnabled else { return }
        let wasShowing = isShowingLevels
        settings.isEnabled = enabled
        scheduleSave()
        guard isShowingLevels != wasShowing else { return }
        if isShowingLevels {
            showEveryOwnersLevel(over: Self.switchRamp)
        } else {
            // The user is watching, so fade rather than restore, which would jump.
            for (display, level) in shown where level < .full {
                backend.apply(.full, to: display, over: Self.switchRamp)
            }
        }
    }

    /// Something outside the app put every display back to its original curve: the watchdog's
    /// restorer, after the app hung. The backend restores and re-captures each original, and every
    /// owned display fades back to its owner's level, as after unlocking.
    public func restoredFromOutside() {
        backend.restore()
        showEveryOwnersLevel(over: Self.switchRamp)
    }

    /// Saves `level` as the app's app setting. If the app owns a display, the display shows the new
    /// level straight away.
    public func setLevel(_ level: Level, for app: AppID) {
        settings.appSettings[app] = level
        settingsChanged()
    }

    /// How far a level hotkey steps a level.
    public static let hotkeyStep = 0.1

    /// A level hotkey: steps the app's level by `hotkeyStep`, to a whole percent, and saves it as its app setting,
    /// creating one if the app had none. Every display it owns fades to the new level over
    /// `switchRamp`.
    ///
    /// An ignored app changes nothing, so a hotkey pressed over Spotlight never changes the app behind it.
    ///
    /// - Returns: the new level, or nil for an ignored app.
    @discardableResult public func nudgeLevel(of app: App, _ direction: NudgeDirection) -> Level? {
        guard !ignoredApps.contains(app.id) else { return nil }
        let step = direction == .up ? Self.hotkeyStep : -Self.hotkeyStep
        // Rounded to a whole percent, so repeated steps don't drift (0.4 - 0.1 isn't 0.3 in binary).
        let level = Level(((level(for: app.id).fraction + step) * 100).rounded() / 100)
        settings.appSettings[app.id] = level
        scheduleSave()
        for (display, owner) in owners where owner.id == app.id && !isHeldForSwitch(display, at: level) {
            show(level, on: display, over: Self.switchRamp)
        }
        return level
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

    /// Every app setting, for the Apps list, sorted by name. App settings aren't saved with names,
    /// so `installedName` looks each app up on this Mac: its name, or nil if it isn't installed.
    /// An app without a bundle ID shows by its file name, and an uninstalled app with one by its
    /// bundle ID.
    public func savedApps(installedName: (AppID) -> String?) -> [SavedApp] {
        settings.appSettings
            .map { app, level in
                let installed = installedName(app)
                let name = app.fileName ?? installed ?? app.rawValue
                return SavedApp(id: app, name: name, level: level, isInstalled: installed != nil)
            }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The global hotkeys the user has bound. None until the user binds one.
    public var hotkeys: [HotkeyAction: Hotkey] { settings.hotkeys }

    /// Binds `hotkey` to `action`, or clears the action's hotkey if nil, and saves the change. A key
    /// combination does one thing, so binding one already used by another action moves it.
    public func setHotkey(_ hotkey: Hotkey?, for action: HotkeyAction) {
        if let hotkey {
            settings.hotkeys = settings.hotkeys.filter { $0.value != hotkey }
        }
        settings.hotkeys[action] = hotkey
        scheduleSave()
    }

    /// The level for any app without its own app setting.
    public var defaultLevel: Level { settings.defaultLevel }

    /// Changes the default level. Every display owned by an app without an app setting shows the
    /// new level straight away.
    public func setDefaultLevel(_ level: Level) {
        settings.defaultLevel = level
        settingsChanged()
    }

    /// Whether anything could be dimmed: dimming is on, the engine isn't suspended, and the default
    /// level or some app setting is below 100%. Only then is it worth watching windows for ownership
    /// changes.
    public var needsWindowTracking: Bool {
        isShowingLevels && (settings.defaultLevel < .full || settings.appSettings.values.contains { $0 < .full })
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
        pendingSettingsApply?.cancel()
        pendingSettingsApply = nil
        backend.restore()
    }

    /// The level `display` should show: its owner's level, or 100% if it's unowned.
    private func target(for display: DisplayID) -> Level {
        owners[display].map { level(for: $0.id) } ?? .full
    }

    /// Fades every display not showing its target, such as one dimmed early for a switch that ended
    /// elsewhere or never ended.
    private func showEveryTargetNotShown() {
        for (display, level) in shown where level != target(for: display) {
            show(target(for: display), on: display, over: Self.switchRamp)
        }
    }

    private func show(_ level: Level, on display: DisplayID, over ramp: Duration) {
        guard notDimming[display] == nil else { return }
        shown[display] = level
        if isShowingLevels { backend.apply(level, to: display, over: ramp) }
    }

    private func stopShowing(on display: DisplayID, because status: DisplayStatus) {
        notDimming[display] = status
        // It shows another app's colours, or its own curve, now, not anything of ours.
        shown[display] = nil
    }

    /// Shows every owned display at its owner's level, for a backend that has just been restored.
    /// Unowned displays already show their original curve.
    private func showEveryOwnersLevel(over ramp: Duration) {
        shown = [:]
        for display in owners.keys {
            show(target(for: display), on: display, over: ramp)
        }
    }

    /// Shows each owner's new level without a ramp, at most once per `settingsApplyInterval`, and
    /// saves the settings once the save delay passes with no further change.
    private func settingsChanged() {
        scheduleSave()
        // A change already waiting will pick this one up.
        guard pendingSettingsApply == nil else { return }
        let sinceLast = lastSettingsApply.map { clock.now - $0 } ?? Self.settingsApplyInterval
        if sinceLast >= Self.settingsApplyInterval {
            applySettings()
        } else {
            pendingSettingsApply = clock.schedule(after: Self.settingsApplyInterval - sinceLast) { [weak self] in
                self?.pendingSettingsApply = nil
                self?.applySettings()
            }
        }
    }

    /// Shows each owner's level straight away where it changed.
    private func applySettings() {
        lastSettingsApply = clock.now
        // Only displays whose level changed, so a display still fading after a switch isn't cut short.
        for display in owners.keys where shown[display] != target(for: display) {
            if isHeldForSwitch(display, at: target(for: display)) { continue }
            show(target(for: display), on: display, over: .zero)
        }
    }

    /// Whether showing `level` on `display` must wait for a switch under way: mid-switch, a display
    /// dimmed early for the app coming to the front is never brightened, so the old window doesn't
    /// flash bright. `appActivated` sets it right.
    private func isHeldForSwitch(_ display: DisplayID, at level: Level) -> Bool {
        activating != nil && level > shown[display, default: .full]
    }

    /// Saves the settings once the save delay passes with no further change.
    private func scheduleSave() {
        pendingSave?.cancel()
        pendingSave = clock.schedule(after: Self.saveDelay) { [weak self] in
            self?.savePendingChanges()
        }
    }
}

/// Whether a display takes levels.
public enum DisplayStatus: Sendable {
    /// It shows its owner's level, or 100% if it's unowned.
    case dimming
    /// Another app controls its colours (`CONTEXT.md`, paused display). It stays paused until the
    /// user chooses Resume.
    case paused
    /// Levels don't take on it, as on some HDR, Sidecar or AirPlay displays
    /// (`CONTEXT.md`, unsupported display).
    case unsupported
}

/// Which way a level hotkey steps a level.
public enum NudgeDirection: Sendable {
    /// Brighter, towards 100%.
    case up
    /// Dimmer, towards the 10% floor.
    case down
}

/// What the status icon shows.
public enum DimmingState: Sendable {
    /// The master switch is off.
    case off
    /// Dimming is on, but every display shows 100%.
    case nothingDimmed
    /// At least one display is dimmed.
    case dimmed
}
