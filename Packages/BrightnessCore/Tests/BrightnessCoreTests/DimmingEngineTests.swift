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

    @Test func switchingToADimmerAppDimsAsSoonAsTheSwitchStarts() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.appActivating(notion, on: builtIn)

        #expect(backend.levels[builtIn] == Level(0.4))
        #expect(engine.owner(of: builtIn) == terminal)
        engine.appActivated(notion, on: builtIn)
        #expect(engine.owner(of: builtIn) == notion)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    @Test func switchingToABrighterAppWaitsUntilItsWindowIsInFront() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.appActivating(terminal, on: builtIn)

        #expect(backend.levels[builtIn] == Level(0.4))
        engine.appActivated(terminal, on: builtIn)
        #expect(backend.levels[builtIn] == .full)
    }

    @Test func anIgnoredAppStartingASwitchChangesNothing() {
        store.saved.appSettings[cathemeral.id] = Level(0.2)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.appActivating(cathemeral, on: builtIn)

        #expect(backend.levels[builtIn] == .full)
    }

    @Test func aDisplayDimmedEarlyForAnAppThatEndsUpElsewhereGoesBackToItsOwnersLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.appActivating(notion, on: builtIn)
        engine.appActivated(notion, on: external)

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == .full)
        #expect(backend.levels[external] == Level(0.4))
    }

    @Test func aSwitchThatIsReplacedBeforeItsWindowComesForwardLeavesNoEarlyDimming() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.appActivating(notion, on: builtIn)
        engine.appActivating(terminal, on: builtIn)
        engine.appActivated(terminal, on: builtIn)

        #expect(backend.levels[builtIn] == .full)
    }

    @Test func bringingAnAppToTheFrontFadesToItsLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()

        engine.appActivated(notion, on: builtIn)

        #expect(backend.levels[builtIn] == Level(0.4))
        #expect(backend.ramps[builtIn] == DimmingEngine.switchRamp)
        #expect(DimmingEngine.switchRamp == .milliseconds(150))
    }

    @Test func dimmingEarlyForASwitchFades() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.appActivating(notion, on: builtIn)

        #expect(backend.ramps[builtIn] == DimmingEngine.switchRamp)
    }

    @Test func aDisplayDimmedEarlyForAnAppThatEndsUpElsewhereFadesBack() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.appActivating(notion, on: builtIn)
        engine.appActivated(notion, on: DisplayID(2))

        #expect(backend.levels[builtIn] == .full)
        #expect(backend.ramps[builtIn] == DimmingEngine.switchRamp)
    }

    @Test func slidingTheOwnersLevelAppliesStraightAway() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.setLevel(Level(0.55), for: notion.id)

        #expect(backend.levels[builtIn] == Level(0.55))
        #expect(backend.ramps[builtIn] == .zero)
    }

    @Test func slidingTheDefaultLevelAppliesStraightAway() {
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.setDefaultLevel(Level(0.6))

        #expect(backend.levels[builtIn] == Level(0.6))
        #expect(backend.ramps[builtIn] == .zero)
    }

    @Test func useDefaultAppliesStraightAway() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.useDefault(for: notion.id)

        #expect(backend.levels[builtIn] == .full)
        #expect(backend.ramps[builtIn] == .zero)
    }

    @Test func aSettingsChangeLeavesDisplaysItDoesNotAffectAlone() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.appActivated(terminal, on: external)
        let before = backend.applied.count

        engine.setLevel(Level(0.3), for: notion.id)

        #expect(backend.applied.count == before + 1)
        #expect(backend.applied.last?.display == builtIn)
    }

    // MARK: Multiple displays

    @Test func eachDisplayKeepsItsOwnOwnerWhenFocusMovesToAnotherDisplay() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[safari.id] = .full
        let engine = makeEngine()
        engine.appActivated(notion, on: external)

        engine.appActivating(safari, on: builtIn)
        engine.appActivated(safari, on: builtIn)

        #expect(engine.owner(of: external) == notion)
        #expect(engine.owner(of: builtIn) == safari)
        #expect(backend.levels[external] == Level(0.4))
        #expect(backend.levels[builtIn] == .full)
    }

    @Test func afterADisplayChangeEveryOwnedDisplayIsReappliedWithoutARamp() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.7)
        let engine = makeEngine()
        engine.appActivated(notion, on: external)
        engine.appActivated(terminal, on: builtIn)
        let before = backend.applied.count

        engine.displaysChanged(to: [builtIn, external])

        #expect(backend.restoreCount == 1)
        let reapplied = backend.applied.dropFirst(before)
        #expect(Set(reapplied.map(\.display)) == [builtIn, external])
        #expect(reapplied.allSatisfy { $0.ramp == .zero })
        #expect(backend.levels[external] == Level(0.4))
        #expect(backend.levels[builtIn] == Level(0.7))
    }

    @Test func aRemovedDisplayIsDroppedAndNoLongerWritten() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: external)
        engine.appActivated(terminal, on: builtIn)
        let before = backend.applied.count

        engine.displaysChanged(to: [builtIn])

        #expect(engine.owner(of: external) == nil)
        #expect(engine.displays == [builtIn])
        #expect(!backend.applied.dropFirst(before).contains { $0.display == external })
        engine.setLevel(Level(0.3), for: notion.id)
        #expect(!backend.applied.dropFirst(before).contains { $0.display == external })
    }

    // MARK: Lock, other users and sleep

    @Test func whileSuspendedEveryDisplayIsRestoredAndNothingIsWritten() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.setSuspended(true)
        let afterSuspend = backend.applied.count
        engine.appActivating(terminal, on: builtIn)
        engine.appActivated(terminal, on: builtIn)
        engine.setLevel(Level(0.3), for: terminal.id)

        #expect(backend.restoreCount == 1)
        #expect(backend.applied.count == afterSuspend)
        #expect(engine.owner(of: builtIn) == terminal)
    }

    @Test func onReturnEveryOwnedDisplayFadesBackToItsOwnersLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.appActivated(terminal, on: external)
        engine.setSuspended(true)
        engine.setLevel(Level(0.6), for: terminal.id)
        let before = backend.applied.count

        engine.setSuspended(false)

        let reapplied = backend.applied.dropFirst(before)
        #expect(Set(reapplied.map(\.display)) == [builtIn, external])
        #expect(reapplied.allSatisfy { $0.ramp == DimmingEngine.switchRamp })
        #expect(backend.levels[builtIn] == Level(0.4))
        #expect(backend.levels[external] == Level(0.6))
    }

    @Test func aDisplayChangeWhileSuspendedWaitsForTheReturnToReapply() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.setSuspended(true)
        let before = backend.applied.count

        engine.displaysChanged(to: [builtIn])
        #expect(backend.applied.count == before)

        engine.setSuspended(false)
        #expect(backend.levels[builtIn] == Level(0.4))
    }
}
