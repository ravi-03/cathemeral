import BrightnessCore
import Testing

/// The Settings window's Apps list.
@MainActor @Suite struct SavedAppsTests {
    let store = RecordingSettingsStore()

    func makeEngine() -> DimmingEngine {
        DimmingEngine(backend: RecordingBackend(), store: store, clock: TestClock(), selfID: cathemeral.id)
    }

    /// Every app is installed, under the name it has in `names`.
    func installed(_ names: [AppID: String]) -> (AppID) -> String? {
        { names[$0] }
    }

    @Test func everySavedAppSettingIsListedByNameWhetherOrNotTheAppIsRunning() {
        store.saved.appSettings = [notion.id: Level(0.4), terminal.id: Level(0.8), safari.id: .full]
        let engine = makeEngine()

        let apps = engine.savedApps(
            installedName: installed([
                notion.id: "Notion", terminal.id: "Terminal", safari.id: "safari",
            ]))

        #expect(apps.map(\.name) == ["Notion", "safari", "Terminal"])
        #expect(apps.map(\.level) == [Level(0.4), .full, Level(0.8)])
        #expect(apps.map(\.isInstalled) == [true, true, true])
    }

    @Test func anAppWithoutABundleIDShowsByItsFileName() throws {
        let tool = try #require(AppID(bundleID: nil, executablePath: "/usr/local/bin/tool"))
        store.saved.appSettings = [tool: Level(0.5)]
        let engine = makeEngine()

        let apps = engine.savedApps(installedName: installed([tool: "Some Other Name"]))

        #expect(apps.map(\.name) == ["tool"])
        #expect(apps.map(\.isInstalled) == [true])
    }

    @Test func anUninstalledAppIsListedAsNotInstalled() throws {
        let tool = try #require(AppID(bundleID: nil, executablePath: "/usr/local/bin/tool"))
        store.saved.appSettings = [notion.id: Level(0.4), tool: Level(0.5)]
        let engine = makeEngine()

        let apps = engine.savedApps(installedName: installed([:]))

        // With no name to go on, a bundle ID app shows by its bundle ID.
        #expect(apps.map(\.name) == ["notion.id", "tool"])
        #expect(apps.map(\.isInstalled) == [false, false])
    }

    @Test func removingAnAppSettingTakesItOffTheListAndTheAppFollowsTheDefaultLevel() {
        store.saved.defaultLevel = Level(0.7)
        store.saved.appSettings = [notion.id: Level(0.4), terminal.id: Level(0.8)]
        let engine = makeEngine()

        engine.useDefault(for: notion.id)

        #expect(engine.savedApps(installedName: installed([:])).map(\.id) == [terminal.id])
        #expect(engine.level(for: notion.id) == Level(0.7))
    }

    @Test func aLevelChangedInTheListShowsThere() {
        store.saved.appSettings = [notion.id: Level(0.4)]
        let engine = makeEngine()

        engine.setLevel(Level(0.6), for: notion.id)

        #expect(engine.savedApps(installedName: installed([:])).map(\.level) == [Level(0.6)])
    }
}
