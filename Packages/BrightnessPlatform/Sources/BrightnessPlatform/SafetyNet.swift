import Dispatch
import Foundation

/// Makes sure the screen is never left dim, whatever happens to the app.
///
/// - **Termination signals** (SIGTERM, SIGINT, SIGHUP) skip `applicationWillTerminate`, so they
///   call `beforeExit` (restore gamma, save) and then exit.
/// - **Death** needs nothing: macOS resets a gamma writer's tables when it exits, even on SIGKILL.
/// - **Hangs** are caught by the watchdog helper, which this keeps running. It writes a heartbeat
///   byte down a pipe every 250 ms from the main run loop. After 1.5 s without one (both numbers
///   are set here and passed to the watchdog), the watchdog
///   resets every display through its restorer and sends SIGUSR1, which arrives as
///   `onRestoredFromOutside` once the main thread runs again.
///
/// If the watchdog dies, the next heartbeat write fails or its exit is noticed, and a new one is
/// launched. The watchdog never writes gamma, so its death leaves the screen as it is.
/// How gamma behaves across processes is in `docs/platform/gamma.md`.
@MainActor public final class SafetyNet {
    /// Twice as often as the 500 ms first planned: a main-thread pause under 1 s then leaves a gap
    /// of at most 1.25 s, well inside the watchdog's 1.5 s timeout, instead of right at it.
    private static let heartbeatInterval: TimeInterval = 0.25

    /// How long the watchdog waits without a heartbeat before treating the app as hung, passed to it
    /// as `--timeout-ms`. The two numbers only work together, so both live here:
    /// - A main-thread pause under 1 s leaves a gap of at most 1 s + `heartbeatInterval` = 1.25 s,
    ///   0.25 s (17%) inside this timeout, so it never triggers a restore.
    /// - A hang is restored within this timeout plus the restorer's spawn time (60–135 ms, ticket
    ///   01): at most about 1.64 s against the 2 s promise, 18% inside it.
    private static let heartbeatTimeoutMilliseconds = 1500

    /// A watchdog that dies within this long of its launch is relaunched only after this long, so
    /// a watchdog that can't start doesn't spin.
    private static let relaunchBackoff: TimeInterval = 1

    private let watchdogURL: URL
    private let beforeExit: @MainActor () -> Void
    private let onRestoredFromOutside: @MainActor () -> Void

    private var isRunning = false
    private var watchdog: Process?
    private var heartbeat: FileHandle?
    private var lastLaunch: ContinuousClock.Instant?
    private var heartbeatTimer: Timer?
    private var signalSources: [any DispatchSourceSignal] = []
    private var activity: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - watchdog: the `GammaWatchdog` executable.
    ///   - beforeExit: restores gamma and saves, before a termination signal exits the app.
    ///   - onRestoredFromOutside: the watchdog reset every display while the app was hung.
    public init(
        watchdog: URL, beforeExit: @escaping @MainActor () -> Void,
        onRestoredFromOutside: @escaping @MainActor () -> Void
    ) {
        watchdogURL = watchdog
        self.beforeExit = beforeExit
        self.onRestoredFromOutside = onRestoredFromOutside
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        for terminationSignal in [SIGTERM, SIGINT, SIGHUP] {
            handle(terminationSignal) { [beforeExit] in
                beforeExit()
                exit(0)
            }
        }
        handle(SIGUSR1) { [onRestoredFromOutside] in onRestoredFromOutside() }
        // App Nap would slow the heartbeat timer down and look like a hang. Idle sleep stays allowed.
        activity = ProcessInfo.processInfo.beginActivity(
            options: .userInitiatedAllowingIdleSystemSleep, reason: "Watchdog heartbeat")
        let timer = Timer(timeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.beat() }
        }
        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        heartbeatTimer = timer
        launchWatchdog()
    }

    /// Stops the heartbeat and lets the watchdog go: it sees the pipe close and exits.
    public func stop() {
        guard isRunning else { return }
        isRunning = false
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        for source in signalSources { source.cancel() }
        signalSources = []
        activity.map(ProcessInfo.processInfo.endActivity)
        activity = nil
        watchdog = nil
        try? heartbeat?.close()
        heartbeat = nil
    }

    private func handle(_ signalNumber: Int32, _ handler: @escaping @MainActor () -> Void) {
        signal(signalNumber, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { handler() } }
        source.resume()
        signalSources.append(source)
    }

    private func launchWatchdog() {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = watchdogURL
        process.arguments = [String(getpid()), "--timeout-ms", String(Self.heartbeatTimeoutMilliseconds)]
        process.standardInput = pipe.fileHandleForReading
        process.terminationHandler = { [weak self] exited in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.replace(exited) } }
        }
        let writeEnd = pipe.fileHandleForWriting.fileDescriptor
        // A failed write must return an error, not raise SIGPIPE (which would kill the app) or block
        // the main thread on a full pipe.
        _ = fcntl(writeEnd, F_SETNOSIGPIPE, 1)
        _ = fcntl(writeEnd, F_SETFL, fcntl(writeEnd, F_GETFL) | O_NONBLOCK)
        lastLaunch = .now
        do {
            try process.run()
        } catch {
            FileHandle.standardError.write(Data("SafetyNet: can't launch the watchdog: \(error)\n".utf8))
            relaunchAfterBackoff()
            return
        }
        try? pipe.fileHandleForReading.close()  // Only the watchdog reads, so its exit closes the pipe.
        watchdog = process
        heartbeat = pipe.fileHandleForWriting
        beat()
    }

    private func beat() {
        guard let heartbeat, let watchdog else { return }
        var byte: UInt8 = 1
        guard write(heartbeat.fileDescriptor, &byte, 1) != 1 else { return }
        // EAGAIN: the pipe is full, so the watchdog stopped reading and can't catch a hang.
        // EPIPE: the watchdog is gone. Either way it needs replacing.
        if errno != EINTR { replace(watchdog) }
    }

    /// Replaces `dead` with a new watchdog, unless it was already replaced or the safety net stopped.
    private func replace(_ dead: Process) {
        guard isRunning, dead === watchdog else { return }
        if dead.isRunning { kill(dead.processIdentifier, SIGKILL) }
        watchdog = nil
        try? heartbeat?.close()
        heartbeat = nil
        if let lastLaunch, ContinuousClock.now - lastLaunch < .seconds(Self.relaunchBackoff) {
            relaunchAfterBackoff()
        } else {
            launchWatchdog()
        }
    }

    private func relaunchAfterBackoff() {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.relaunchBackoff) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isRunning, self.watchdog == nil else { return }
                self.launchWatchdog()
            }
        }
    }
}
