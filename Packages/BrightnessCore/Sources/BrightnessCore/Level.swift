/// How far an app's content is dimmed, from 10% (dimmest allowed) to 100% (not dimmed).
///
/// Every level is clamped to the 10% floor when it is made, so no level below the floor can
/// ever reach a gamma write.
public struct Level: Hashable, Comparable, Sendable, CustomStringConvertible {
    /// The dimmest level allowed. A fixed constant, not a setting.
    public static let floor = 0.1

    /// Not dimmed.
    public static let full = Level(1.0)

    /// The level as a fraction, always in `floor...1.0`.
    public let fraction: Double

    /// Clamps `fraction` to `floor...1.0`. A NaN becomes the floor.
    public init(_ fraction: Double) {
        self.fraction = fraction.isNaN ? Self.floor : min(max(fraction, Self.floor), 1.0)
    }

    public static func < (lhs: Level, rhs: Level) -> Bool { lhs.fraction < rhs.fraction }

    public var description: String { "\(Int((fraction * 100).rounded()))%" }
}
