/// One display's gamma transfer table: a curve per colour channel.
///
/// Values are `Float` because CoreGraphics' `CGGammaValue` is a `Float`.
public struct GammaTable: Equatable, Sendable {
    public var red: [Float]
    public var green: [Float]
    public var blue: [Float]

    public init(red: [Float], green: [Float], blue: [Float]) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// This table, taken as a display's captured original curve, dimmed to `level`.
    ///
    /// Every entry of every channel is scaled by the level, so the display's calibration is kept.
    /// At 100% the original comes back unchanged.
    public func scaled(to level: Level) -> GammaTable {
        guard level < .full else { return self }
        let factor = Float(level.fraction)
        return GammaTable(
            red: red.map { $0 * factor },
            green: green.map { $0 * factor },
            blue: blue.map { $0 * factor }
        )
    }
}
