import CoreGraphics
import Foundation

/// The one-shot restorer, run by the watchdog as `GammaWatchdog restore` when the app hangs.
///
/// It writes each display's current table back unchanged, so nothing changes on screen, and exits.
/// Its exit as a gamma writer makes WindowServer reset every display to its ColorSync curve,
/// which undoes the hung app's dimming (docs/platform/gamma.md). This is the only gamma write
/// allowed outside the gamma backend (CODING_STANDARDS.md).
enum Restorer {
    static func run() -> Never {
        var displays = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(displays.count), &displays, &count) == .success else { exit(1) }
        for display in displays.prefix(Int(count)) {
            let capacity = CGDisplayGammaTableCapacity(display)
            guard capacity > 0 else { continue }
            var red = [CGGammaValue](repeating: 0, count: Int(capacity))
            var green = red
            var blue = red
            var entries: UInt32 = 0
            guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &entries) == .success,
                entries > 0
            else { continue }
            _ = CGSetDisplayTransferByTable(display, entries, red, green, blue)
        }
        exit(0)
    }
}
