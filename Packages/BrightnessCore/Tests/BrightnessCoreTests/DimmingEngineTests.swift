import BrightnessCore
import Testing

@MainActor @Suite struct DimmingEngineTests {
    let backend = RecordingBackend()
    let store = InMemorySettingsStore()
    let clock = TestClock()

    func makeEngine() -> DimmingEngine {
        DimmingEngine(backend: backend, store: store, clock: clock, selfID: cathemeral.id)
    }

    @Test func activationMakesTheAppTheDisplayOwnerAndDimsToItsLevel() {
        store.setAppSetting(Level(0.4), for: notion.id)
        let engine = makeEngine()

        engine.appActivated(notion, on: builtIn)

        #expect(engine.owner(of: builtIn) == notion)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    @Test func anAppWithoutAnAppSettingUsesTheDefaultLevel() {
        store.defaultLevel = Level(0.7)
        let engine = makeEngine()

        engine.appActivated(terminal, on: builtIn)

        #expect(engine.level(for: terminal.id) == Level(0.7))
        #expect(backend.levels[builtIn] == Level(0.7))
    }

    @Test(arguments: [
        App(id: AppID(bundleID: "com.apple.Spotlight"), name: "Spotlight"),
        App(id: AppID(bundleID: "com.apple.dock"), name: "Dock"),
        App(id: AppID(bundleID: "com.apple.notificationcenterui"), name: "Notification Center"),
        App(id: AppID(bundleID: "com.apple.loginwindow"), name: "loginwindow"),
        cathemeral,
    ])
    func anIgnoredAppNeverBecomesTheDisplayOwner(ignored: App) {
        store.setAppSetting(Level(0.4), for: notion.id)
        store.setAppSetting(Level(0.8), for: ignored.id)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.appActivated(ignored, on: builtIn)

        #expect(engine.owner(of: builtIn) == notion)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    @Test func settingTheOwnersLevelChangesItsDisplayLive() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.setLevel(Level(0.55), for: notion.id)

        #expect(engine.level(for: notion.id) == Level(0.55))
        #expect(backend.levels[builtIn] == Level(0.55))
    }

    @Test func settingTheLevelOfAnAppThatOwnsNoDisplayOnlySavesIt() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.setLevel(Level(0.3), for: terminal.id)

        #expect(backend.levels[builtIn] == Level.full)
        engine.appActivated(terminal, on: builtIn)
        #expect(backend.levels[builtIn] == Level(0.3))
    }

    @Test func aLevelBelowTenPercentIsClampedToTheFloor() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.setLevel(Level(0.02), for: notion.id)

        #expect(engine.level(for: notion.id).fraction == 0.1)
        #expect(backend.applied.allSatisfy { $0.level.fraction >= 0.1 })
        #expect(backend.levels[builtIn]?.fraction == 0.1)
    }

    @Test func aDefaultLevelBelowTenPercentIsClampedToTheFloor() {
        store.defaultLevel = Level(-1)
        let engine = makeEngine()

        engine.appActivated(terminal, on: builtIn)

        #expect(backend.levels[builtIn]?.fraction == 0.1)
    }

    @Test func restoringPutsEveryDisplayBackToItsOriginalCurve() {
        store.setAppSetting(Level(0.4), for: notion.id)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.restore()

        #expect(backend.restoreCount == 1)
    }

    @Test func bringingAFullLevelAppToTheFrontUndimsTheDisplay() {
        store.setAppSetting(Level(0.4), for: notion.id)
        store.setAppSetting(.full, for: terminal.id)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.appActivated(terminal, on: builtIn)

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == .full)
    }
}
