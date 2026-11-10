import BrightnessCore

/// Records every level the engine hands to the screen, per display.
@MainActor final class RecordingBackend: BrightnessBackend {
    private(set) var applied: [(display: DisplayID, level: Level)] = []
    private(set) var restoreCount = 0

    /// The last level applied to each display.
    var levels: [DisplayID: Level] {
        applied.reduce(into: [:]) { $0[$1.display] = $1.level }
    }

    func apply(_ level: Level, to display: DisplayID) {
        applied.append((display, level))
    }

    func restore() {
        restoreCount += 1
    }
}

/// A clock that only moves when a test moves it. Scheduled actions run, in due order, as the
/// test advances past them.
@MainActor final class TestClock: DimmingClock {
    private(set) var now: ContinuousClock.Instant = .now
    private var scheduled: [Scheduled] = []

    private final class Scheduled: ScheduledAction {
        let due: ContinuousClock.Instant
        let action: @MainActor () -> Void
        var isCancelled = false

        init(due: ContinuousClock.Instant, action: @escaping @MainActor () -> Void) {
            self.due = due
            self.action = action
        }

        func cancel() { isCancelled = true }
    }

    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        let item = Scheduled(due: now.advanced(by: delay), action: action)
        scheduled.append(item)
        return item
    }

    func advance(by duration: Duration) {
        let end = now.advanced(by: duration)
        while let next = scheduled.filter({ !$0.isCancelled && $0.due <= end }).min(by: { $0.due < $1.due }) {
            scheduled.removeAll { $0 === next }
            now = next.due
            next.action()
        }
        scheduled.removeAll { $0.isCancelled }
        now = end
    }
}

let builtIn = DisplayID(1)
let cathemeral = App(id: AppID(bundleID: "io.github.ravi-03.cathemeral"), name: "Cathemeral")
let notion = App(id: AppID(bundleID: "notion.id"), name: "Notion")
let terminal = App(id: AppID(bundleID: "com.apple.Terminal"), name: "Terminal")

/// Holds settings in memory and records every save.
@MainActor final class RecordingSettingsStore: SettingsStore {
    /// What `load()` returns. Each save replaces it.
    var saved = Settings()
    private(set) var saveCount = 0

    func load() -> Settings { saved }

    func save(_ settings: Settings) {
        saved = settings
        saveCount += 1
    }
}
