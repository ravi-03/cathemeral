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

/// A clock that only moves when a test moves it.
final class TestClock: DimmingClock {
    private(set) var now: ContinuousClock.Instant = .now

    func advance(by duration: Duration) {
        now = now.advanced(by: duration)
    }
}

let builtIn = DisplayID(1)
let cathemeral = App(id: AppID(bundleID: "io.github.ravi-03.cathemeral"), name: "Cathemeral")
let notion = App(id: AppID(bundleID: "notion.id"), name: "Notion")
let terminal = App(id: AppID(bundleID: "com.apple.Terminal"), name: "Terminal")
