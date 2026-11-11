/// Reads one display's gamma table back and decides what that says about who controls it.
///
/// The table is read back after our writes and on the 1 Hz window tick. Three ticks in a row
/// where another app's table replaced ours mean that app has taken the display over, so the
/// display is paused (`CONTEXT.md`, paused display). Only a tick where our table survived starts
/// the count again: a read-back straight after our own write always matches, since the last write
/// wins. How gamma behaves across processes is in `docs/platform/gamma.md`.
public struct TableWatch: Sendable {
    /// What the backend should do after a check.
    public enum Action: Equatable, Sendable {
        /// Nothing: the table is ours, or not yet decided.
        case carryOn
        /// The table went back to the captured original, as when any other gamma writer exits.
        /// Write ours again, straight away.
        case reapply
        /// The table went back to the reset curve, or something else while nothing of ours was on
        /// screen. Capture the table on screen now as the original, and dim on top of it.
        case recapture
        /// Another app controls the display's colours. Stop writing to it.
        case pause
        /// Our writes never take on this display, as on some HDR, Sidecar or AirPlay displays.
        /// Stop writing to it.
        case unsupported
    }

    /// How many ticks in a row with another app's table, or with the table reset, pause the
    /// display. A table reset every tick means something keeps writing the original back, and
    /// re-applying would flash once a second.
    public static let checksToPause = 3

    /// How many writes in a row that leave the original curve on screen, before any write has
    /// taken, mark the display unsupported.
    public static let untakenWritesToGiveUp = 3

    /// How far apart two entries may be and still match. WindowServer may store a table at a lower
    /// precision than it was written, and an 8-bit step is about 0.004, so this covers rounding to
    /// half a step either way. Another app's table, or a reset from a dimmed table, differs by far
    /// more.
    static let tolerance: Float = 0.003

    private let original: GammaTable
    private let resetCurve: GammaTable
    private var foreignTicks = 0
    private var resetTicks = 0

    /// Whether any write has been read back as written. Until one has, a read-back showing the
    /// original means the write didn't take, not that something reset the table.
    private var aWriteHasTaken = false
    private var untakenWrites = 0

    /// - Parameters:
    ///   - original: the display's captured original curve.
    ///   - resetCurve: the curve WindowServer resets the display to when a gamma writer exits, if
    ///     that isn't `original`: after Resume, `original` holds the other app's colours.
    public init(original: GammaTable, resetCurve: GammaTable? = nil) {
        self.original = original
        self.resetCurve = resetCurve ?? original
    }

    /// Checks the table read back straight after writing `written`.
    public mutating func afterWrite(_ written: GammaTable, readBack: GammaTable) -> Action {
        if readBack.matches(written) {
            aWriteHasTaken = true
            return .carryOn
        }
        if readBack.matches(original) {
            guard aWriteHasTaken else {
                untakenWrites += 1
                return untakenWrites >= Self.untakenWritesToGiveUp ? .unsupported : .carryOn
            }
            return .reapply
        }
        if readBack.matches(resetCurve) { return .recapture }
        // Another app wrote in the moment between our write and the read. The ticks decide.
        return .carryOn
    }

    /// Checks the table read back on the window tick, when the display is dimmed and the last table
    /// written was `expected`.
    public mutating func onTick(expecting expected: GammaTable, readBack: GammaTable) -> Action {
        if readBack.matches(expected) {
            aWriteHasTaken = true
            foreignTicks = 0
            resetTicks = 0
            return .carryOn
        }
        let reset = readBack.matches(original) ? Action.reapply : readBack.matches(resetCurve) ? .recapture : nil
        if let reset {
            resetTicks += 1
            return resetTicks >= Self.checksToPause ? .pause : reset
        }
        foreignTicks += 1
        return foreignTicks >= Self.checksToPause ? .pause : .carryOn
    }

    /// Checks the table read back on the window tick, when the display shows 100% and none of our
    /// tables is on screen. Another curve is no fight, but the next dim must scale it.
    public func onTickUndimmed(readBack: GammaTable) -> Action {
        readBack.matches(original) ? .carryOn : .recapture
    }
}

extension GammaTable {
    /// Whether every channel matches `other`'s within `TableWatch.tolerance`. Tables with different
    /// entry counts are compared at each entry of the longer one, reading the shorter one between
    /// its entries.
    fileprivate func matches(_ other: GammaTable) -> Bool {
        Self.matches(red, other.red) && Self.matches(green, other.green) && Self.matches(blue, other.blue)
    }

    private static func matches(_ a: [Float], _ b: [Float]) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return a.isEmpty && b.isEmpty }
        let (longer, shorter) = a.count >= b.count ? (a, b) : (b, a)
        return longer.indices.allSatisfy { index in
            abs(longer[index] - value(of: shorter, at: Float(index) / Float(max(longer.count - 1, 1))))
                <= TableWatch.tolerance
        }
    }

    /// The curve's value at `position` (0 to 1 along it), between its two nearest entries.
    private static func value(of curve: [Float], at position: Float) -> Float {
        let place = position * Float(curve.count - 1)
        let below = Int(place.rounded(.down))
        let above = min(below + 1, curve.count - 1)
        let weight = place - Float(below)
        return curve[below] * (1 - weight) + curve[above] * weight
    }
}
