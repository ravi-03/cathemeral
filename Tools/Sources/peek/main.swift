// Prints the largest value in each online display's gamma table, one line per display:
// `<display-id> <peak>`. With `--built-in`, prints only the built-in display's peak. An undimmed calibrated curve peaks at about 1.0, and a display dimmed
// to a level peaks at about that level.
//
// Never writes gamma, so its exit never resets a display (docs/platform/gamma.md). Reads are
// global, so it sees the tables any other process wrote.
import CoreGraphics
import Foundation

var ids = [CGDirectDisplayID](repeating: 0, count: 32)
var count: UInt32 = 0
guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else {
    FileHandle.standardError.write(Data("peek: can't list displays\n".utf8))
    exit(1)
}
let builtInOnly = CommandLine.arguments.contains("--built-in")
for display in ids.prefix(Int(count)) where !builtInOnly || CGDisplayIsBuiltin(display) != 0 {
    let capacity = CGDisplayGammaTableCapacity(display)
    var red = [CGGammaValue](repeating: 0, count: Int(capacity))
    var green = red
    var blue = red
    var entries: UInt32 = 0
    guard capacity > 0,
        CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &entries) == .success,
        entries > 0
    else {
        print("\(display) unreadable")
        continue
    }
    let n = Int(entries)
    let peak = max(red.prefix(n).max()!, green.prefix(n).max()!, blue.prefix(n).max()!)
    print(builtInOnly ? String(format: "%.4f", peak) : String(format: "%u %.4f", display, peak))
}
