import BrightnessCore
import CoreGraphics
import Dispatch

/// Shows levels by scaling each display's gamma table from its captured original curve.
///
/// How gamma behaves across processes is in `docs/platform/gamma.md`: the last write wins, and
/// `CGDisplayRestoreColorSyncSettings` undoes only this process's own writes.
@MainActor public final class GammaController: BrightnessBackend {
    /// Each display's curve as it was before our first write to it.
    private var originals: [DisplayID: GammaTable] = [:]

    /// Writes can block for several milliseconds, so they run off the main actor, in order.
    private let writes = DispatchQueue(label: "io.github.ravi-03.cathemeral.gamma-writes")

    public init() {}

    public func apply(_ level: Level, to display: DisplayID) {
        guard let original = originals[display] ?? captureOriginal(of: display) else { return }
        let table = original.scaled(to: level)
        writes.async { Self.write(table, to: display) }
    }

    public func restore() {
        writes.sync {}  // Let queued writes land first, so none lands after the restore.
        CGDisplayRestoreColorSyncSettings()
    }

    /// Captures the display's current curve. Called only before our first write to that display,
    /// so our own curve is never captured as the original.
    private func captureOriginal(of display: DisplayID) -> GammaTable? {
        let original = Self.read(display)
        originals[display] = original
        return original
    }

    private nonisolated static func read(_ display: DisplayID) -> GammaTable? {
        let capacity = CGDisplayGammaTableCapacity(display.rawValue)
        guard capacity > 0 else { return nil }
        var red = [CGGammaValue](repeating: 0, count: Int(capacity))
        var green = red
        var blue = red
        var count: UInt32 = 0
        let result = CGGetDisplayTransferByTable(display.rawValue, capacity, &red, &green, &blue, &count)
        guard result == .success, count > 0 else { return nil }
        let n = Int(count)
        return GammaTable(red: Array(red.prefix(n)), green: Array(green.prefix(n)), blue: Array(blue.prefix(n)))
    }

    private nonisolated static func write(_ table: GammaTable, to display: DisplayID) {
        _ = CGSetDisplayTransferByTable(
            display.rawValue, UInt32(table.red.count), table.red, table.green, table.blue)
    }
}
