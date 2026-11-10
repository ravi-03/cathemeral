import BrightnessCore
import Testing

@Suite struct FaderTests {
    let start = ContinuousClock.now
    let refresh = Duration.milliseconds(16)
    let duration = Duration.milliseconds(150)

    func ms(_ milliseconds: Int) -> ContinuousClock.Instant { start + .milliseconds(milliseconds) }

    @Test func theFirstFrameIsOneRefreshIntoTheRampHoweverLateItArrives() {
        var onTime = Fader()
        var late = Fader()
        onTime.fade(to: Level(0.4), over: duration)
        late.fade(to: Level(0.4), over: duration)

        let first = onTime.nextFrame(shownAt: ms(16), refresh: refresh)!
        let firstAfterAStall = late.nextFrame(shownAt: ms(200), refresh: refresh)

        let expected = Ramp(from: .full, to: Level(0.4), duration: duration).level(after: refresh)
        #expect(first == expected)
        #expect(firstAfterAStall == expected)
        #expect(first < .full)
    }

    @Test func aFadeEndsExactlyOnItsTargetAndStops() {
        var fader = Fader()
        fader.fade(to: Level(0.4), over: duration)

        var frames: [Level] = []
        for frame in 1...12 where fader.isFading {
            frames.append(fader.nextFrame(shownAt: ms(frame * 16), refresh: refresh)!)
        }

        #expect(frames.last == Level(0.4))
        #expect(!fader.isFading)
        #expect(fader.onScreen == Level(0.4))
    }

    @Test func anInterruptedFadeContinuesFromTheLevelOnScreen() {
        var fader = Fader()
        fader.fade(to: Level(0.4), over: duration)
        let shown = fader.nextFrame(shownAt: ms(16), refresh: refresh)!

        // No frames for 50 ms (a busy main thread), then a switch back.
        fader.fade(to: .full, over: duration)
        let next = fader.nextFrame(shownAt: ms(82), refresh: refresh)

        #expect(next == Ramp(from: shown, to: .full, duration: duration).level(after: refresh))
    }

    @Test func fadingToTheTargetAlreadyUnderWayDoesNotRestartIt() {
        var fader = Fader()
        var undisturbed = Fader()
        fader.fade(to: Level(0.4), over: duration)
        undisturbed.fade(to: Level(0.4), over: duration)
        _ = fader.nextFrame(shownAt: ms(16), refresh: refresh)
        _ = undisturbed.nextFrame(shownAt: ms(16), refresh: refresh)

        fader.fade(to: Level(0.4), over: duration)

        #expect(
            fader.nextFrame(shownAt: ms(32), refresh: refresh)
                == undisturbed.nextFrame(shownAt: ms(32), refresh: refresh))
    }

    @Test func aFadeWithNoDurationJumpsStraightToItsTarget() {
        var fader = Fader()

        fader.fade(to: Level(0.55), over: .zero)

        #expect(fader.nextFrame(shownAt: ms(16), refresh: refresh) == Level(0.55))
        #expect(!fader.isFading)
    }

    @Test func jumpingFinishesAFadeAtOnce() {
        var fader = Fader()
        fader.fade(to: Level(0.4), over: duration)

        #expect(fader.jump() == Level(0.4))
        #expect(!fader.isFading)
        #expect(fader.onScreen == Level(0.4))
    }

    @Test func aFaderAtItsTargetIsNotFading() {
        var fader = Fader(at: Level(0.4))

        fader.fade(to: Level(0.4), over: duration)

        #expect(!fader.isFading)
    }

    @Test func aStallMidFadeCarriesOnFromTheLevelOnScreenInsteadOfJumpingAhead() {
        var stalled = Fader()
        var steady = Fader()
        stalled.fade(to: Level(0.4), over: duration)
        steady.fade(to: Level(0.4), over: duration)
        let first = stalled.nextFrame(shownAt: ms(16), refresh: refresh)!
        _ = steady.nextFrame(shownAt: ms(16), refresh: refresh)

        // The next frame comes 80 ms late, after a busy main thread.
        let afterTheStall = stalled.nextFrame(shownAt: ms(96), refresh: refresh)!

        #expect(afterTheStall == steady.nextFrame(shownAt: ms(32), refresh: refresh))
        #expect(afterTheStall < first)
    }

    @Test func aSecondFrameForTheSameRefreshIsSkipped() {
        var fader = Fader()
        var undisturbed = Fader()
        fader.fade(to: Level(0.4), over: duration)
        undisturbed.fade(to: Level(0.4), over: duration)
        _ = fader.nextFrame(shownAt: ms(16), refresh: refresh)
        _ = undisturbed.nextFrame(shownAt: ms(16), refresh: refresh)

        #expect(fader.nextFrame(shownAt: ms(19), refresh: refresh) == nil)
        #expect(
            fader.nextFrame(shownAt: ms(32), refresh: refresh)
                == undisturbed.nextFrame(shownAt: ms(32), refresh: refresh))
    }

    @Test func aFrameThatLandsTooLateForItsRefreshCountsForTheNextOne() {
        var late = Fader()
        var onTime = Fader()
        late.fade(to: Level(0.4), over: duration)
        onTime.fade(to: Level(0.4), over: duration)
        _ = late.nextFrame(shownAt: ms(16), refresh: refresh)
        _ = onTime.nextFrame(shownAt: ms(16), refresh: refresh)

        // Its write took until after the refresh at 16 ms, so it shows at 32 ms instead.
        late.frameLanded(at: ms(21), refresh: refresh)

        #expect(late.nextFrame(shownAt: ms(32), refresh: refresh) == nil)
        #expect(
            late.nextFrame(shownAt: ms(48), refresh: refresh)
                == onTime.nextFrame(shownAt: ms(32), refresh: refresh))
    }

    @Test func aFrameThatLandsInTimeChangesNothing() {
        var fader = Fader()
        var undisturbed = Fader()
        fader.fade(to: Level(0.4), over: duration)
        undisturbed.fade(to: Level(0.4), over: duration)
        _ = fader.nextFrame(shownAt: ms(16), refresh: refresh)
        _ = undisturbed.nextFrame(shownAt: ms(16), refresh: refresh)

        fader.frameLanded(at: ms(10), refresh: refresh)

        #expect(
            fader.nextFrame(shownAt: ms(32), refresh: refresh)
                == undisturbed.nextFrame(shownAt: ms(32), refresh: refresh))
    }
}
