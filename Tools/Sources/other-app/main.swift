// Stands in for another app that writes gamma, such as f.lux, so `e2e.sh` can check paused
// displays. It captures the built-in display's table at launch, then takes commands on stdin:
//
//   write <fraction>   write the captured table scaled by <fraction>, as f.lux tinting the display
//   touch              write the table on screen now back unchanged (a write that changes nothing)
//   keep <fraction>    write that scaled table every 50 ms until the next command, as f.lux
//                      re-asserting its colours over another app's writes
//
// It prints `READY` once listening, then one line per command. It exits at end of input, and its
// exit makes WindowServer reset every display (docs/platform/gamma.md), which is how `e2e.sh`
// checks that a reset is re-applied. Start it before anything dims the display, so the table it
// captures is the original curve.
import CoreGraphics
import Foundation

func say(_ line: String) {
    print(line)
    fflush(stdout)
}

func table(of display: CGDirectDisplayID) -> (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue])? {
    let capacity = CGDisplayGammaTableCapacity(display)
    guard capacity > 0 else { return nil }
    var red = [CGGammaValue](repeating: 0, count: Int(capacity))
    var green = red
    var blue = red
    var count: UInt32 = 0
    guard CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0
    else { return nil }
    let n = Int(count)
    return (Array(red.prefix(n)), Array(green.prefix(n)), Array(blue.prefix(n)))
}

nonisolated func write(
    _ table: (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]), to display: CGDirectDisplayID
) {
    _ = CGSetDisplayTransferByTable(display, UInt32(table.red.count), table.red, table.green, table.blue)
}

func builtInDisplay() -> CGDirectDisplayID? {
    var ids = [CGDirectDisplayID](repeating: 0, count: 32)
    var count: UInt32 = 0
    guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return nil }
    return ids.prefix(Int(count)).first { CGDisplayIsBuiltin($0) != 0 }
}

guard let builtIn = builtInDisplay(), let original = table(of: builtIn) else {
    FileHandle.standardError.write(Data("other-app: can't read the built-in display's table\n".utf8))
    exit(1)
}

/// The captured table scaled by `fraction`, as another app's tint.
func tinted(_ fraction: Float) -> (red: [CGGammaValue], green: [CGGammaValue], blue: [CGGammaValue]) {
    (original.red.map { $0 * fraction }, original.green.map { $0 * fraction }, original.blue.map { $0 * fraction })
}

/// The `keep` timer, if one is running. Any command stops it.
var keeping: DispatchSourceTimer?

say("READY")
while let line = readLine() {
    keeping?.cancel()
    keeping = nil
    let command = line.split(separator: " ")
    switch (command.first, command.count) {
    case ("write", 2), ("keep", 2):
        guard let fraction = Float(command[1]) else {
            say("bad fraction: \(command[1])")
            continue
        }
        let table = tinted(fraction)
        write(table, to: builtIn)
        if command[0] == "keep" {
            let timer = DispatchSource.makeTimerSource(queue: .global())
            timer.schedule(deadline: .now() + .milliseconds(50), repeating: .milliseconds(50))
            timer.setEventHandler { write(table, to: builtIn) }
            timer.resume()
            keeping = timer
        }
        say("\(command[0]) \(command[1])")
    case ("touch", 1):
        if let current = table(of: builtIn) { write(current, to: builtIn) }
        say("touched")
    default:
        say("unknown command: \(line)")
    }
}
say("end of input: exiting")
