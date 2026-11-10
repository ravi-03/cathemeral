import BrightnessCore
import Testing

@MainActor @Suite struct DimmingEngineTests {
    let backend = RecordingBackend()
    let store = RecordingSettingsStore()
    let clock = TestClock()

    func makeEngine() -> DimmingEngine {
        DimmingEngine(backend: backend, store: store, clock: clock, selfID: cathemeral.id)
    }

    @Test func activationMakesTheAppTheDisplayOwnerAndDimsToItsLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()

        engine.appActivated(notion, on: builtIn)

        #expect(engine.owner(of: builtIn) == notion)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    @Test func anAppWithoutAnAppSettingUsesTheDefaultLevel() {
        store.saved.defaultLevel = Level(0.7)
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
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[ignored.id] = Level(0.8)
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
        store.saved.defaultLevel = Level(-1)
        let engine = makeEngine()

        engine.appActivated(terminal, on: builtIn)

        #expect(backend.levels[builtIn]?.fraction == 0.1)
    }

    @Test func restoringPutsEveryDisplayBackToItsOriginalCurve() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.restore()

        #expect(backend.restoreCount == 1)
    }

    @Test func bringingAFullLevelAppToTheFrontUndimsTheDisplay() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = .full
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.appActivated(terminal, on: builtIn)

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == .full)
    }

    @Test func aChangeIsSaved300MillisecondsLater() {
        let engine = makeEngine()

        engine.setLevel(Level(0.4), for: notion.id)
        clock.advance(by: .milliseconds(299))
        #expect(store.saveCount == 0)

        clock.advance(by: .milliseconds(1))
        #expect(store.saveCount == 1)
        #expect(store.saved.appSettings[notion.id] == Level(0.4))
    }

    @Test func changesInQuickSuccessionAreSavedOnceAfterTheLast() {
        let engine = makeEngine()

        engine.setLevel(Level(0.4), for: notion.id)
        clock.advance(by: .milliseconds(200))
        engine.setLevel(Level(0.5), for: notion.id)
        clock.advance(by: .milliseconds(200))
        engine.setLevel(Level(0.6), for: notion.id)
        clock.advance(by: .milliseconds(299))
        #expect(store.saveCount == 0)

        clock.advance(by: .milliseconds(1))
        #expect(store.saveCount == 1)
        #expect(store.saved.appSettings[notion.id] == Level(0.6))
        clock.advance(by: .seconds(5))
        #expect(store.saveCount == 1)
    }

    @Test func savingPendingChangesWritesThemStraightAway() {
        let engine = makeEngine()
        engine.setLevel(Level(0.4), for: notion.id)

        engine.savePendingChanges()

        #expect(store.saveCount == 1)
        #expect(store.saved.appSettings[notion.id] == Level(0.4))
        clock.advance(by: .seconds(1))
        #expect(store.saveCount == 1)
    }

    @Test func withNoPendingChangesNothingIsSaved() {
        let engine = makeEngine()

        engine.savePendingChanges()

        #expect(store.saveCount == 0)
    }

    @Test func changingTheDefaultLevelChangesOnlyAppsWithoutAnAppSetting() {
        let external = DisplayID(2)
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.appActivated(terminal, on: external)

        engine.setDefaultLevel(Level(0.6))

        #expect(engine.defaultLevel == Level(0.6))
        #expect(backend.levels[builtIn] == Level(0.4))
        #expect(backend.levels[external] == Level(0.6))
        #expect(engine.level(for: terminal.id) == Level(0.6))
    }

    @Test func theDefaultLevelIsSaved() {
        let engine = makeEngine()

        engine.setDefaultLevel(Level(0.6))
        clock.advance(by: DimmingEngine.saveDelay)

        #expect(store.saved.defaultLevel == Level(0.6))
    }

    @Test func useDefaultRemovesTheAppSettingAndTheAppFollowsTheDefaultLevel() {
        store.saved.defaultLevel = Level(0.7)
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        #expect(engine.hasAppSetting(for: notion.id))

        engine.useDefault(for: notion.id)

        #expect(!engine.hasAppSetting(for: notion.id))
        #expect(backend.levels[builtIn] == Level(0.7))
        engine.setDefaultLevel(Level(0.5))
        #expect(backend.levels[builtIn] == Level(0.5))
        clock.advance(by: DimmingEngine.saveDelay)
        #expect(store.saved.appSettings[notion.id] == nil)
    }

    @Test func settingsSavedOnOneLaunchAreUsedOnTheNext() {
        let first = makeEngine()
        first.setLevel(Level(0.4), for: notion.id)
        first.savePendingChanges()

        let next = makeEngine()
        next.appActivated(notion, on: builtIn)

        #expect(backend.levels[builtIn] == Level(0.4))
    }
}
