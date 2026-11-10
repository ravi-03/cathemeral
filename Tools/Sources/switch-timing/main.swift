// Checks that switching apps never shows either app brighter than its own level. Brightening for
// the new app must wait until its window has reached the front, or the old app's window flashes
// bright. Dimming for it must happen by the time its window reaches the front, or the new app's
// window flashes bright.
//
//   switch-timing <bundle-id> <bundle-id> [rounds]
//
// Run it while Cathemeral or the harness is dimming, with different levels for the two apps. It
// brings each app to the front in turn, and watches the window list and the gamma table every
// millisecond. It prints `ok` or `FAIL` per switch and exits non-zero on any failure.
//
// Never writes gamma, so its exit never resets a display (docs/platform/gamma.md).
import AppKit

/// How far a gamma change may be on the wrong side of the window reaching the front and still
/// pass. Both are sampled in the same 1 ms loop.
let tolerance = 2.0

/// One sample of what is on screen, timed in milliseconds.
struct Sample {
    var time: Double
    var topmostPID: pid_t?
    var gammaPeak: Float
}

func milliseconds() -> Double { Double(DispatchTime.now().uptimeNanoseconds) / 1e6 }

func topmostPID() -> pid_t? {
    let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
    let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return windows.first { ($0[kCGWindowLayer as String] as? Int) == 0 }?[kCGWindowOwnerPID as String] as? pid_t
}

/// The largest value in the main display's gamma table, rounded to hundredths.
func gammaPeak() -> Float {
    let display = CGMainDisplayID()
    let capacity = CGDisplayGammaTableCapacity(display)
    var red = [CGGammaValue](repeating: 0, count: Int(capacity))
    var green = red
    var blue = red
    var count: UInt32 = 0
    guard capacity > 0,
        CGGetDisplayTransferByTable(display, capacity, &red, &green, &blue, &count) == .success, count > 0
    else { return -1 }
    let n = Int(count)
    let peak = max(red.prefix(n).max()!, green.prefix(n).max()!, blue.prefix(n).max()!)
    return (peak * 100).rounded() / 100
}

/// Samples the screen for `duration` milliseconds.
func watch(for duration: Double) -> [Sample] {
    var samples: [Sample] = []
    let end = milliseconds() + duration
    while milliseconds() < end {
        samples.append(Sample(time: milliseconds(), topmostPID: topmostPID(), gammaPeak: gammaPeak()))
        usleep(1000)
    }
    return samples
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: switch-timing <bundle-id> <bundle-id> [rounds]\n".utf8))
    exit(2)
}
let bundleIDs = Array(arguments.prefix(2))
let rounds = arguments.count > 2 ? Int(arguments[arguments.startIndex + 2]) ?? 4 : 4

var failures = 0
for round in 0..<(rounds * 2) {
    let bundleID = bundleIDs[round % 2]
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-b", bundleID]
    try open.run()
    let samples = watch(for: 1000)
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    else {
        print("FAIL  \(bundleID): not running")
        failures += 1
        continue
    }
    let first = samples[0]
    let inFront = samples.first { $0.topmostPID == pid }
    let gammaChange = samples.first { $0.gammaPeak != first.gammaPeak }
    switch (inFront, gammaChange) {
    case (nil, _):
        print("FAIL  \(bundleID): its window never reached the front")
        failures += 1
    case (_, nil):
        print("skip  \(bundleID): gamma didn't change (same level as the app before it?)")
    case (let inFront?, let gammaChange?):
        // Positive: gamma changed after the window reached the front.
        let lag = gammaChange.time - inFront.time
        let dimming = gammaChange.gammaPeak < first.gammaPeak
        let when = String(format: "%.1f ms %@ its window reached the front", abs(lag), lag < 0 ? "before" : "after")
        if first.topmostPID == pid {
            print("skip  \(bundleID): already in front")
        } else if dimming ? lag > tolerance : lag < -tolerance {
            print("FAIL  \(bundleID): \(dimming ? "dimmed" : "brightened") \(when)")
            failures += 1
        } else {
            print("ok    \(bundleID): \(dimming ? "dimmed" : "brightened") \(when)")
        }
    }
}
exit(failures > 0 ? 1 : 0)
