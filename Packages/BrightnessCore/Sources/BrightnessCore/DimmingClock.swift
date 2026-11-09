/// The engine's sense of time, injected so tests can control it.
public protocol DimmingClock: AnyObject {
    var now: ContinuousClock.Instant { get }
}

/// The real clock.
public final class SystemClock: DimmingClock {
    public init() {}

    public var now: ContinuousClock.Instant { .now }
}
