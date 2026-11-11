// The watchdog helper. Cathemeral launches it at startup as
// `GammaWatchdog <app-pid> --timeout-ms <ms>`, with the read end of its heartbeat pipe on stdin,
// and writes a byte down that pipe every 250 ms from its main run loop. `SafetyNet` in
// BrightnessPlatform owns both the heartbeat interval and the timeout, and why they fit together.
//
// - End of file: the app died. macOS has already reset its gamma, so the watchdog just exits.
// - No byte for the timeout: the app is hung. The watchdog runs the restorer (`GammaWatchdog restore`,
//   see Restorer.swift), whose exit makes WindowServer reset every display, then sends the app
//   SIGUSR1 so it fades its levels back in if it recovers. One restore per hang.
//
// The watchdog itself never writes gamma (CODING_STANDARDS.md): if it did, its own exit would
// reset the app's dimming. How gamma behaves across processes is in docs/platform/gamma.md.
import Foundation

if CommandLine.arguments.dropFirst().first == "restore" {
    Restorer.run()
}

let arguments = CommandLine.arguments
guard arguments.count == 4, let appPID = pid_t(arguments[1]), arguments[2] == "--timeout-ms",
    let heartbeatTimeout = Int32(arguments[3]), heartbeatTimeout > 0
else {
    FileHandle.standardError.write(
        Data("usage: GammaWatchdog <app-pid> --timeout-ms <ms> | GammaWatchdog restore\n".utf8))
    exit(64)
}

/// WindowServer resets the displays about 65 ms after a gamma writer exits (ticket 01). The app is
/// signalled only after that, so a re-apply from an app that has just recovered isn't wiped by
/// the reset.
let resetSettleTime: useconds_t = 200_000

func log(_ message: String) {
    FileHandle.standardError.write(Data("watchdog[\(getpid())]: \(message)\n".utf8))
}

/// Runs the restorer and waits for it to exit. Its exit, not anything this process does, resets
/// the displays.
func runRestorer() {
    let restorer = Process()
    restorer.executableURL = Bundle.main.executableURL
    restorer.arguments = ["restore"]
    restorer.standardInput = FileHandle.nullDevice
    do {
        try restorer.run()
        restorer.waitUntilExit()
    } catch {
        log("can't run the restorer: \(error)")
    }
}

log("watching app \(appPID)")
var restoredThisHang = false
var heartbeat = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
var buffer = [UInt8](repeating: 0, count: 64)
while true {
    let ready = poll(&heartbeat, 1, heartbeatTimeout)
    if ready < 0 {
        if errno == EINTR { continue }
        log("poll failed (errno \(errno)), exiting")
        exit(1)
    }
    if ready == 0 {
        if kill(appPID, 0) != 0, errno == ESRCH {
            log("app is gone, exiting")
            exit(0)
        }
        guard !restoredThisHang else { continue }
        restoredThisHang = true
        let start = ContinuousClock.now
        runRestorer()
        let restorerTime = ContinuousClock.now - start
        usleep(resetSettleTime)
        kill(appPID, SIGUSR1)
        log("no heartbeat for \(heartbeatTimeout) ms: app hung, restored (restorer took \(restorerTime))")
        continue
    }
    let count = read(STDIN_FILENO, &buffer, buffer.count)
    if count < 0, errno == EINTR || errno == EAGAIN { continue }
    if count <= 0 {
        log("heartbeat pipe closed: app quit or died, exiting")
        exit(0)
    }
    if restoredThisHang {
        log("heartbeat back")
        restoredThisHang = false
    }
}
