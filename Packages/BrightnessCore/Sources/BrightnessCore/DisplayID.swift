/// A display, as CoreGraphics numbers it (`CGDirectDisplayID`).
public struct DisplayID: Hashable, Sendable, CustomStringConvertible {
    public let rawValue: UInt32

    public init(_ rawValue: UInt32) {
        self.rawValue = rawValue
    }

    public var description: String { "display \(rawValue)" }
}
