import BrightnessCore
import Testing

@Suite struct RampTests {
    let duration = Duration.milliseconds(150)

    func ramp(from: Double = 1.0, to: Double = 0.4) -> Ramp {
        Ramp(from: Level(from), to: Level(to), duration: duration)
    }

    @Test func aRampStartsAtItsStartingLevel() {
        #expect(ramp().level(after: .zero) == Level(1.0))
    }

    @Test func aRampEndsExactlyAtItsTarget() {
        #expect(ramp().level(after: duration) == Level(0.4))
        #expect(ramp().level(after: .seconds(5)) == Level(0.4))
    }

    @Test func aRampEasesOutCoveringMostOfTheChangeEarly() {
        let halfway = ramp(from: 1.0, to: 0.4).level(after: duration / 2)

        // A linear ramp would be at 0.7. Ease-out is past it, but not yet at the target.
        #expect(halfway < Level(0.6))
        #expect(halfway > Level(0.4))
    }

    @Test(arguments: [(1.0, 0.4), (0.4, 1.0)])
    func aRampMovesSteadilyTowardsItsTargetWithShrinkingSteps(from: Double, to: Double) {
        let levels = (0...15).map { ramp(from: from, to: to).level(after: .milliseconds($0 * 10)).fraction }
        let steps = zip(levels, levels.dropFirst()).map { abs($1 - $0) }

        #expect(zip(levels, levels.dropFirst()).allSatisfy { from > to ? $1 <= $0 : $1 >= $0 })
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $1 <= $0 + 1e-12 })
    }

    @Test func aRampWithNoDurationIsAtItsTargetStraightAway() {
        #expect(Ramp(from: .full, to: Level(0.4), duration: .zero).level(after: .zero) == Level(0.4))
    }
}
