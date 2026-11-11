import BrightnessCore
import Testing

@Suite struct TableWatchTests {
    let original = GammaTable(red: [0, 0.5, 1], green: [0, 0.5, 1], blue: [0, 0.5, 1])
    /// Another app's table, such as f.lux warming the display.
    let foreign = GammaTable(red: [0, 0.5, 1], green: [0, 0.45, 0.9], blue: [0, 0.35, 0.7])
    var dimmed: GammaTable { original.scaled(to: Level(0.4)) }

    @Test func aReadBackEqualToWhatWasWrittenIsFine() {
        var watch = TableWatch(original: original)

        #expect(watch.afterWrite(dimmed, readBack: dimmed) == .carryOn)
        #expect(watch.onTick(expecting: dimmed, readBack: dimmed) == .carryOn)
    }

    @Test func threeForeignTablesInARowPauseTheDisplay() {
        var watch = TableWatch(original: original)
        _ = watch.afterWrite(dimmed, readBack: dimmed)

        #expect(watch.onTick(expecting: dimmed, readBack: foreign) == .carryOn)
        #expect(watch.onTick(expecting: dimmed, readBack: foreign) == .carryOn)
        #expect(watch.onTick(expecting: dimmed, readBack: foreign) == .pause)
    }

    @Test func ourTableSurvivingATickStartsTheCountAgain() {
        var watch = TableWatch(original: original)
        _ = watch.afterWrite(dimmed, readBack: dimmed)

        _ = watch.onTick(expecting: dimmed, readBack: foreign)
        _ = watch.onTick(expecting: dimmed, readBack: foreign)
        _ = watch.onTick(expecting: dimmed, readBack: dimmed)

        #expect(watch.onTick(expecting: dimmed, readBack: foreign) == .carryOn)
        #expect(watch.onTick(expecting: dimmed, readBack: foreign) == .carryOn)
    }

    @Test func ourOwnWriteBetweenForeignTablesDoesNotStartTheCountAgain() {
        // An app switch writes over the other app's colours, so its read-back always matches. If
        // that cleared the count, switching often would keep the two apps fighting.
        var watch = TableWatch(original: original)
        _ = watch.afterWrite(dimmed, readBack: dimmed)

        _ = watch.onTick(expecting: dimmed, readBack: foreign)
        _ = watch.afterWrite(dimmed, readBack: dimmed)
        _ = watch.onTick(expecting: dimmed, readBack: foreign)
        _ = watch.afterWrite(dimmed, readBack: dimmed)

        #expect(watch.onTick(expecting: dimmed, readBack: foreign) == .pause)
    }

    @Test func aTableResetEveryTickPausesTheDisplay() {
        // Something keeps writing the original curve back, so re-applying would flash every second.
        var watch = TableWatch(original: original)
        _ = watch.afterWrite(dimmed, readBack: dimmed)

        #expect(watch.onTick(expecting: dimmed, readBack: original) == .reapply)
        #expect(watch.onTick(expecting: dimmed, readBack: original) == .reapply)
        #expect(watch.onTick(expecting: dimmed, readBack: original) == .pause)
    }

    @Test func afterResumeAResetToTheEarlierCurveRecapturesIt() {
        // Resume captured the other app's colours as the original. When that app quits, the display
        // resets to the curve it had before, which is a reset too.
        var watch = TableWatch(original: foreign, resetCurve: original)
        let dimmedForeign = foreign.scaled(to: Level(0.4))
        _ = watch.afterWrite(dimmedForeign, readBack: dimmedForeign)

        #expect(watch.onTick(expecting: dimmedForeign, readBack: original) == .recapture)
        #expect(watch.onTick(expecting: dimmedForeign, readBack: foreign) == .reapply)
    }

    @Test func anUndimmedDisplayShowingAnotherCurveIsRecaptured() {
        // Nothing of ours is on screen, so there's no fight, but the next dim must scale the curve
        // on screen now, not the stale one.
        var watch = TableWatch(original: original)

        #expect(watch.onTickUndimmed(readBack: original) == .carryOn)
        #expect(watch.onTickUndimmed(readBack: foreign) == .recapture)
    }

    @Test func aTableResetToTheOriginalIsReappliedWithoutCountingTowardPausing() {
        var watch = TableWatch(original: original)
        _ = watch.afterWrite(dimmed, readBack: dimmed)
        _ = watch.onTick(expecting: dimmed, readBack: foreign)
        _ = watch.onTick(expecting: dimmed, readBack: foreign)

        #expect(watch.onTick(expecting: dimmed, readBack: original) == .reapply)
        #expect(watch.afterWrite(dimmed, readBack: original) == .reapply)
    }

    @Test func aDisplayWhereWritesNeverTakeIsUnsupported() {
        var watch = TableWatch(original: original)

        #expect(watch.afterWrite(dimmed, readBack: original) == .carryOn)
        #expect(watch.afterWrite(dimmed, readBack: original) == .carryOn)
        #expect(watch.afterWrite(dimmed, readBack: original) == .unsupported)
    }

    @Test func aWriteThatTookOnceMeansTheDisplayIsSupported() {
        var watch = TableWatch(original: original)
        _ = watch.afterWrite(dimmed, readBack: dimmed)

        for _ in 0..<5 {
            #expect(watch.afterWrite(dimmed, readBack: original) == .reapply)
        }
    }

    @Test func tablesWithinRoundingOfEachOtherMatch() {
        var watch = TableWatch(original: original)
        let rounded = GammaTable(
            red: dimmed.red.map { $0 + 0.001 }, green: dimmed.green.map { $0 - 0.001 }, blue: dimmed.blue)

        #expect(watch.afterWrite(dimmed, readBack: rounded) == .carryOn)
        for _ in 0..<5 {
            #expect(watch.onTick(expecting: dimmed, readBack: rounded) == .carryOn)
        }
    }

    @Test func aReadBackWithMoreEntriesIsComparedEntryForEntry() {
        var watch = TableWatch(original: original)
        let finer = GammaTable(
            red: [0, 0.1, 0.2, 0.3, 0.4], green: [0, 0.1, 0.2, 0.3, 0.4], blue: [0, 0.1, 0.2, 0.3, 0.4])

        for _ in 0..<5 {
            #expect(watch.onTick(expecting: dimmed, readBack: finer) == .carryOn)
        }
    }
}
