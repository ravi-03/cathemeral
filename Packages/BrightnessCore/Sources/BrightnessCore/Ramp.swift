/// A change of level spread over time with an ease-out curve, so the screen fades instead of
/// jumping: most of the change happens early, then it settles gently onto the target.
public struct Ramp: Equatable, Sendable {
    public let from: Level
    public let to: Level
    public let duration: Duration

    public init(from: Level, to: Level, duration: Duration) {
        self.from = from
        self.to = to
        self.duration = duration
    }

    /// The level `elapsed` into the ramp: `from` at the start, `to` once it ends.
    public func level(after elapsed: Duration) -> Level {
        guard elapsed < duration else { return to }
        let progress = max(0, elapsed / duration)
        return Level(from.fraction + (to.fraction - from.fraction) * Self.easeOut(progress))
    }

    /// Cubic ease-out: 0 at 0, 1 at 1, fastest at the start.
    private static func easeOut(_ progress: Double) -> Double {
        let remaining = 1 - progress
        return 1 - remaining * remaining * remaining
    }
}
