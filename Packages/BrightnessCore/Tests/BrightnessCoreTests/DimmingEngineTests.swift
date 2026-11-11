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

    // MARK: Restored from outside (the watchdog's restorer, during a hang)

    @Test func afterARestoreFromOutsideEveryOwnedDisplayFadesBackToItsOwnersLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.6)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.appActivated(terminal, on: external)
        let before = backend.applied.count

        engine.restoredFromOutside()

        let reapplied = backend.applied.dropFirst(before)
        #expect(backend.restoreCount == 1)
        #expect(Set(reapplied.map(\.display)) == [builtIn, external])
        #expect(reapplied.allSatisfy { $0.ramp == DimmingEngine.switchRamp })
        #expect(backend.levels[builtIn] == Level(0.4))
        #expect(backend.levels[external] == Level(0.6))
    }

    @Test func aRestoreFromOutsideWhileSuspendedWritesNothingUntilTheReturn() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.setSuspended(true)
        let before = backend.applied.count

        engine.restoredFromOutside()
        #expect(backend.applied.count == before)

        engine.setSuspended(false)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    // MARK: Ownership follows windows

    @Test func minimisingTheOwnersLastWindowHandsTheDisplayToTheTopmostVisibleApp() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.7)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.visibleAppsChanged([builtIn: [terminal, safari]])

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == Level(0.7))
        #expect(backend.ramps[builtIn] == DimmingEngine.switchRamp)
    }

    @Test func swipingToAnEmptySpaceLeavesTheDisplayUnownedAtFullLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.visibleAppsChanged([:])

        #expect(engine.owner(of: builtIn) == nil)
        #expect(backend.levels[builtIn] == .full)
        #expect(backend.ramps[builtIn] == DimmingEngine.switchRamp)
    }

    @Test func anIgnoredAppOnTopIsSkippedWhenHandingOver() {
        store.saved.appSettings[terminal.id] = Level(0.7)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.visibleAppsChanged([builtIn: [cathemeral, terminal]])

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == Level(0.7))
    }

    @Test func aDisplayShowingOnlyIgnoredAppsIsUnowned() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        engine.visibleAppsChanged([builtIn: [cathemeral]])

        #expect(engine.owner(of: builtIn) == nil)
    }

    @Test func anOwnerStillVisibleBeneathAnotherAppKeepsTheDisplay() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        let before = backend.applied.count

        engine.visibleAppsChanged([builtIn: [terminal, notion]])

        #expect(engine.owner(of: builtIn) == notion)
        #expect(backend.applied.count == before)
    }

    @Test func focusMovingToAnotherDisplayDoesNotChangeOwnership() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: external)
        engine.appActivated(safari, on: builtIn)
        let before = backend.applied.count

        engine.visibleAppsChanged([builtIn: [safari], external: [notion]])

        #expect(engine.owner(of: external) == notion)
        #expect(engine.owner(of: builtIn) == safari)
        #expect(backend.applied.count == before)
    }

    @Test func anUnownedDisplayPassesToTheTopmostAppThatAppearsOnIt() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)

        engine.visibleAppsChanged([builtIn: [terminal], external: [notion]])

        #expect(engine.owner(of: external) == notion)
        #expect(backend.levels[external] == Level(0.4))
    }

    @Test func hidingTheOwnerHandsTheDisplayToTheAppNowOnTop() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.7)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)

        // A hidden app's windows can still be listed for a moment after the hide.
        engine.appLeft(notion.id, visibleApps: [builtIn: [notion, terminal]])

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == Level(0.7))
    }

    @Test func quittingTheOwnerHandsOverOnlyTheDisplaysItOwned() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.7)
        let engine = makeEngine()
        engine.appActivated(safari, on: external)
        engine.appActivated(notion, on: builtIn)

        engine.appLeft(notion.id, visibleApps: [builtIn: [terminal], external: [safari]])

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(engine.owner(of: external) == safari)
        #expect(backend.levels[builtIn] == Level(0.7))
    }

    @Test func withNothingSetBelowFullLevelWindowsNeedNoTracking() {
        store.saved.defaultLevel = .full
        store.saved.appSettings[notion.id] = .full
        let engine = makeEngine()

        #expect(!engine.needsWindowTracking)
    }

    @Test func anAppSettingBelowFullLevelNeedsWindowTrackingUntilItIsRemoved() {
        store.saved.defaultLevel = .full
        let engine = makeEngine()

        engine.setLevel(Level(0.4), for: notion.id)
        #expect(engine.needsWindowTracking)

        engine.useDefault(for: notion.id)
        #expect(!engine.needsWindowTracking)
    }

    @Test func aDefaultLevelBelowFullLevelNeedsWindowTracking() {
        store.saved.defaultLevel = .full
        let engine = makeEngine()

        engine.setDefaultLevel(Level(0.8))

        #expect(engine.needsWindowTracking)
    }

    @Test func anAppThatLeavesWhileItsSwitchIsUnderWayLeavesNoEarlyDimming() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)
        engine.appActivating(notion, on: builtIn)

        engine.appLeft(notion.id, visibleApps: [builtIn: [terminal]])

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.levels[builtIn] == .full)
    }

    @Test func draggingTheOwnersWindowToADisplayAnotherAppOwnsLeavesThatDisplaysOwner() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(safari, on: external)
        engine.appActivated(notion, on: builtIn)

        engine.visibleAppsChanged([external: [notion, safari]])

        #expect(engine.owner(of: builtIn) == nil)
        #expect(backend.levels[builtIn] == .full)
        #expect(engine.owner(of: external) == safari)
        #expect(backend.levels[external] == .full)
    }

    @Test func anAppThatOwnsNoDisplayLeavingChangesNothing() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        let before = backend.applied.count

        engine.appLeft(terminal.id, visibleApps: [builtIn: [notion]])

        #expect(engine.owner(of: builtIn) == notion)
        #expect(backend.applied.count == before)
    }

    @Test func aHandoverDuringASwitchNeverBrightensADisplayDimmedEarly() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(terminal, on: builtIn)
        engine.appActivating(notion, on: builtIn)

        engine.visibleAppsChanged([builtIn: [safari]])

        #expect(engine.owner(of: builtIn) == safari)
        #expect(backend.levels[builtIn] == Level(0.4))
        engine.appActivated(notion, on: builtIn)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    @Test func handingOverToAnAppAtTheSameLevelLeavesTheDisplayAlone() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        let before = backend.applied.count

        engine.visibleAppsChanged([builtIn: [terminal]])

        #expect(engine.owner(of: builtIn) == terminal)
        #expect(backend.applied.count == before)
    }

    @Test func whileSuspendedWindowsNeedNoTracking() {
        store.saved.defaultLevel = Level(0.5)
        let engine = makeEngine()

        engine.setSuspended(true)
        #expect(!engine.needsWindowTracking)

        engine.setSuspended(false)
        #expect(engine.needsWindowTracking)
    }

    @Test func aPausedDisplayGetsNoTargetWhileOtherDisplaysCarryOn() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.6)
        let engine = makeEngine()
        engine.appActivated(safari, on: builtIn)
        engine.appActivated(safari, on: external)

        engine.displayPaused(builtIn)
        engine.appActivated(notion, on: builtIn)
        engine.appActivated(terminal, on: external)
        engine.setLevel(Level(0.3), for: notion.id)
        engine.displaysChanged(to: [builtIn, external])

        #expect(engine.status(of: builtIn) == .paused)
        #expect(!backend.applied.contains { $0.display == builtIn && $0.level < .full })
        #expect(backend.levels[external] == Level(0.6))
    }

    @Test func resumeRecapturesTheDisplayAndFadesToItsOwnersLevel() {
        store.saved.appSettings[notion.id] = Level(0.4)
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.displayPaused(builtIn)
        engine.setLevel(Level(0.3), for: notion.id)

        engine.resume(builtIn)

        #expect(engine.status(of: builtIn) == .dimming)
        #expect(backend.resumed == [builtIn])
        #expect(backend.levels[builtIn] == Level(0.3))
        #expect(backend.ramps[builtIn] == DimmingEngine.switchRamp)
    }

    @Test func aDisplayPausedAgainAfterResumeStaysPaused() {
        let engine = makeEngine()
        engine.appActivated(notion, on: builtIn)
        engine.displayPaused(builtIn)
        engine.resume(builtIn)

        engine.displayPaused(builtIn)
        clock.advance(by: .seconds(60))
        engine.displaysChanged(to: [builtIn])

        #expect(engine.status(of: builtIn) == .paused)
    }

    @Test func anUnsupportedDisplayGetsNoTargetUntilTheDisplaysChange() {
        store.saved.appSettings[notion.id] = Level(0.4)
        store.saved.appSettings[terminal.id] = Level(0.6)
        let engine = makeEngine()
        engine.appActivated(safari, on: builtIn)

        engine.displayUnsupported(builtIn)
        engine.appActivated(notion, on: builtIn)

        #expect(engine.status(of: builtIn) == .unsupported)
        #expect(backend.levels[builtIn] == .full)

        engine.displaysChanged(to: [builtIn])

        #expect(engine.status(of: builtIn) == .dimming)
        #expect(backend.levels[builtIn] == Level(0.4))
    }

    @Test func eachWindowTickChecksTheTablesExceptWhileSuspended() {
        let engine = makeEngine()

        engine.visibleAppsChanged([builtIn: [notion]])
        engine.visibleAppsChanged([builtIn: [notion]])
        engine.setSuspended(true)
        engine.visibleAppsChanged([builtIn: [notion]])

        #expect(backend.checkCount == 2)
    }

    @Test func anyPausedDisplayIsReportedForTheStatusIcon() {
        let engine = makeEngine()
        #expect(!engine.hasPausedDisplay)

        engine.displayPaused(external)
        #expect(engine.hasPausedDisplay)

        engine.resume(external)
        #expect(!engine.hasPausedDisplay)
    }
}
