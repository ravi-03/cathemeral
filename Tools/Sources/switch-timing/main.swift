// Checks that switching apps fades, and never shows either app brighter than its own level. Brightening for
// the new app must wait until its window has reached the front, or the old app's window flashes
// bright. Dimming for it must happen by the time its window reaches the front, or the new app's
// window flashes bright. Each switch must fade through several levels rather than jump, and
// rapid switching back and forth must never jump either.
//
//   switch-timing <bundle-id> <bundle-id> [rounds]
//
// Run it while Cathemeral or the harness is dimming, with different levels for the two apps. It
// brings each app to the front in turn, and watches the window list and the gamma table every
// millisecond. It prints `ok` or `FAIL` per switch and exits non-zero on any failure.
//
// Never writes gamma, so its exit never resets a display (docs/platform/gamma.md).
import AppKit
import os

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

/// Samples the screen for `duration` milliseconds. Gamma is sampled on its own, as fast as it can
/// be read, so no frame of a fade is missed while the slower window list is read on another thread.
/// Each sample carries the topmost window as last seen.
func watch(for duration: Double) -> [Sample] {
    let end = milliseconds() + duration
    let windows = OSAllocatedUnfairLock(initialState: [(time: Double, pid: pid_t?)]())
    let done = DispatchSemaphore(value: 0)
    Thread.detachNewThread {
        while milliseconds() < end {
            let sample = (time: milliseconds(), pid: topmostPID())
            windows.withLock { $0.append(sample) }
            usleep(500)
        }
        done.signal()
    }
    var gamma: [(time: Double, peak: Float)] = []
    while milliseconds() < end {
        gamma.append((milliseconds(), gammaPeak()))
        usleep(250)
    }
    done.wait()
    let windowSamples = windows.withLock { $0 }
    return gamma.map { sample in
        let topmost = windowSamples.last { $0.time <= sample.time }?.pid ?? windowSamples.first?.pid
        return Sample(time: sample.time, topmostPID: topmost, gammaPeak: sample.peak)
    }
}

let arguments = CommandLine.arguments.dropFirst()
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: switch-timing <bundle-id> <bundle-id> [rounds]\n".utf8))
    exit(2)
}
let bundleIDs = Array(arguments.prefix(2))
let rounds = arguments.count > 2 ? Int(arguments[arguments.startIndex + 2]) ?? 4 : 4

/// The biggest share of a change one step may take. A cubic ease-out over 150 ms moves about 29% of
/// the way in its first 60 Hz frame; a jump moves 100%.
let largestStepShare = 0.4

/// Brings the app to the front, as `open -b` does from the Dock or Finder.
@Sendable func bringToFront(_ bundleID: String) throws {
    let open = Process()
    open.executableURL = URL(fileURLWithPath: "/usr/bin/open")
    open.arguments = ["-b", bundleID]
    try open.run()
}

/// Prints each change of level or topmost window, timed from the first sample, so a failure can be
/// read without re-running.
func printTimeline(_ samples: [Sample]) {
    guard let start = samples.first?.time else { return }
    var last: Sample?
    for (previous, sample) in zip([samples[0]] + samples, samples)
    where sample.gammaPeak != last?.gammaPeak || sample.topmostPID != last?.topmostPID {
        print(
            String(
                format: "        %7.1f ms  level %.2f  topmost pid %d  (%.1f ms since the previous sample)",
                sample.time - start, sample.gammaPeak, sample.topmostPID ?? 0, sample.time - previous.time))
        last = sample
    }
}

/// The largest change between two samples in a row.
func largestStep(_ samples: [Sample]) -> Float {
    zip(samples, samples.dropFirst()).map { abs($1.gammaPeak - $0.gammaPeak) }.max() ?? 0
}

var failures = 0
@MainActor func report(_ passed: Bool, _ line: String) {
    print("\(passed ? "ok  " : "FAIL")  \(line)")
    if !passed { failures += 1 }
}

for round in 0..<(rounds * 2) {
    let bundleID = bundleIDs[round % 2]
    try bringToFront(bundleID)
    let samples = watch(for: 1000)
    guard let pid = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
    else {
        report(false, "\(bundleID): not running")
        continue
    }
    let first = samples[0]
    let inFront = samples.first { $0.topmostPID == pid }
    let gammaChange = samples.first { $0.gammaPeak != first.gammaPeak }
    switch (inFront, gammaChange) {
    case (nil, _):
        report(false, "\(bundleID): its window never reached the front")
    case (_, nil):
        print("skip  \(bundleID): gamma didn't change (same level as the app before it?)")
    case (let inFront?, let gammaChange?):
        guard first.topmostPID != pid else {
            print("skip  \(bundleID): already in front")
            continue
        }
        // Positive: gamma changed after the window reached the front.
        let lag = gammaChange.time - inFront.time
        let dimming = gammaChange.gammaPeak < first.gammaPeak
        let verb = dimming ? "dimmed" : "brightened"
        let when = String(format: "%.1f ms %@ its window reached the front", abs(lag), lag < 0 ? "before" : "after")
        report(dimming ? lag <= tolerance : lag >= -tolerance, "\(bundleID): \(verb) \(when)")

        // The fade: every level shown from the first change until it settles.
        let change = abs(samples.last!.gammaPeak - first.gammaPeak)
        let levels = Set(samples.map(\.gammaPeak)).count - 2  // Not counting the start and the end.
        let step = largestStep(samples)
        if levels < 2 || step > Float(largestStepShare) * change { printTimeline(samples) }
        report(
            levels >= 2 && step <= Float(largestStepShare) * change,
            String(
                format: "%@: faded through %d levels, largest step %.0f%% of the change", bundleID, levels,
                step / change * 100))
    }
}

/// Brings the app to the front, waits for any fade to finish, and returns the level then shown.
func settle(on bundleID: String) throws -> Float {
    try bringToFront(bundleID)
    usleep(1_000_000)
    return gammaPeak()
}

// Rapid switching, like holding Cmd-Tab: the level must never jump, however often it is retargeted.
// A burst that reverses mid-fade never covers the whole gap between the two apps' levels, so steps
// are measured against that gap. Each burst starts from one app settled in front, alternating
// which, then switches four times.
let gap = abs(try settle(on: bundleIDs[0]) - (try settle(on: bundleIDs[1])))
for burst in 0..<4 {
    let settled = bundleIDs[burst % 2]
    let other = bundleIDs[(burst + 1) % 2]
    _ = try settle(on: settled)
    Thread.detachNewThread {
        for (index, bundleID) in [other, settled, other, settled].enumerated() {
            if index > 0 { usleep(60_000) }
            try? bringToFront(bundleID)
        }
    }
    let samples = watch(for: 1500)
    let range = (samples.map(\.gammaPeak).max() ?? 0) - (samples.map(\.gammaPeak).min() ?? 0)
    // Starting from the dimmer app, every brightening is usually replaced before its window
    // arrives, so the level barely moves.
    guard range >= 0.05 else {
        print("skip  rapid switching from \(settled): the level barely changed")
        continue
    }
    let step = largestStep(samples)
    if step > Float(largestStepShare) * gap { printTimeline(samples) }
    report(
        step <= Float(largestStepShare) * gap,
        String(
            format: "rapid switching from %@: largest step %.0f%% of the %.2f gap between the apps' levels", settled,
            step / gap * 100, gap))
}
exit(failures > 0 ? 1 : 0)
