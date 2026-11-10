/// Fades one display between levels, one frame per refresh, keeping track of the level actually on
/// screen.
///
/// Frames can arrive late when the main thread is busy. A fade never catches up by jumping ahead:
/// each frame moves at most one refresh along the curve, so after a stall the fade carries on from
/// the level on screen and finishes a little later. For the same reason a fade's first frame is one
/// refresh into the curve however late it arrives, and a new target fades on from the last frame
/// shown.
public struct Fader: Sendable {
    /// The level of the last frame shown.
    public private(set) var onScreen: Level

    private var ramp: Ramp

    /// How far along `ramp` the last frame was.
    private var elapsed = Duration.zero

    /// When the last frame was shown, in any fade.
    private var lastFrame: ContinuousClock.Instant?

    public init(at level: Level = .full) {
        onScreen = level
        ramp = Ramp(from: level, to: level, duration: .zero)
    }

    /// Whether more frames are needed to reach the target.
    public var isFading: Bool { onScreen != ramp.to }

    /// Starts fading from the level on screen to `target` over `duration`. A zero duration jumps on
    /// the next frame. If a fade to `target` is already under way, it carries on undisturbed.
    public mutating func fade(to target: Level, over duration: Duration) {
        guard target != ramp.to || !isFading else { return }
        ramp = Ramp(from: onScreen, to: target, duration: duration)
        elapsed = .zero
    }

    /// The level for the frame that will be shown at `shownAt`, which is now on screen, or nil if
    /// a frame was already made for that refresh (only the last write before a refresh is shown, so
    /// a second one would skip a level).
    /// - Parameter refresh: the time between frames.
    public mutating func nextFrame(shownAt: ContinuousClock.Instant, refresh: Duration) -> Level? {
        let sinceLast = lastFrame.map { shownAt - $0 } ?? refresh
        guard sinceLast >= refresh / 2 else { return nil }
        elapsed += min(sinceLast, refresh)
        lastFrame = shownAt
        onScreen = ramp.level(after: elapsed)
        return onScreen
    }

    /// Finishes the fade at once, for a display with no refresh to time frames by. Returns the target.
    public mutating func jump() -> Level {
        elapsed = ramp.duration
        onScreen = ramp.to
        return onScreen
    }

    /// The last frame's write finished at `time`. A display shows a new table from the first refresh
    /// after the write lands, so a write that landed after the refresh it was made for shows a
    /// refresh or more later, and the frame made for that later refresh is skipped.
    public mutating func frameLanded(at time: ContinuousClock.Instant, refresh: Duration) {
        guard let lastFrame, time > lastFrame else { return }
        self.lastFrame = lastFrame + refresh * ((time - lastFrame) / refresh).rounded(.up)
    }
}
