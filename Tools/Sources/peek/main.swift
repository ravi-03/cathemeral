// Prints the largest value in each online display's gamma table, one line per display:
// `<display-id> <peak>`. With `--built-in`, prints only the built-in display's peak. An undimmed
// calibrated curve peaks at about 1.0, and a display dimmed to a level peaks at about that level.
//
// `--built-in --until <peak> --within <seconds>` waits for the built-in display to show that
// peak, reading every 5 ms, and prints how many milliseconds it took. It exits 1 if the time runs
// out, after printing the last peak it read.
//
// Never writes gamma, so its exit never resets a display (docs/platform/gamma.md). Reads are
// global, so it sees the tables any other process wrote.
import CoreGraphics
import Foundation

func onlineDisplays() -> [CGDirectDisplayID] {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else {
        FileHandle.standardError.write(Data("peek: can't list displays\n".utf8))
        exit(1)
    }
    return Array(ids.prefix(Int(count)))
}

/// The display's peak to four places, or nil if its table can't be read.
func peak(of display: CGDirectDisplayID) -> String? {
    let capacity = CGDisplayGammaTableCapacity(display)
    var red = [CGGammaValue](repeating: 0, count: Int(capacity))
    var green = red
    var blue = red
    var entries: UInt32 = 0
    guard capacity > 0,
        CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &entries) == .success,
        entries > 0
    else { return nil }
    let n = Int(entries)
    return String(format: "%.4f", max(red.prefix(n).max()!, green.prefix(n).max()!, blue.prefix(n).max()!))
}

func value(after flag: String) -> String? {
    CommandLine.arguments.firstIndex(of: flag).flatMap {
        CommandLine.arguments.indices.contains($0 + 1) ? CommandLine.arguments[$0 + 1] : nil
    }
}

let builtInOnly = CommandLine.arguments.contains("--built-in")
if builtInOnly, let target = value(after: "--until") {
    guard let builtIn = onlineDisplays().first(where: { CGDisplayIsBuiltin($0) != 0 }) else { exit(1) }
    let within = Duration.seconds(Double(value(after: "--within") ?? "") ?? 2)
    let start = ContinuousClock.now
    var last: String?
    while ContinuousClock.now - start < within {
        last = peak(of: builtIn)
        if last == target {
            print(String(format: "%.0f", (ContinuousClock.now - start) / .milliseconds(1)))
            exit(0)
        }
        usleep(5_000)
    }
    print("timed out at \(last ?? "unreadable")")
    exit(1)
}
for display in onlineDisplays() where !builtInOnly || CGDisplayIsBuiltin(display) != 0 {
    let shown = peak(of: display) ?? "unreadable"
    print(builtInOnly ? shown : "\(display) \(shown)")
}
