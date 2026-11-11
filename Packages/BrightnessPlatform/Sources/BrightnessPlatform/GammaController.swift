import AppKit
import BrightnessCore
import CoreGraphics
import Dispatch
import QuartzCore
import os

/// Shows levels by scaling each display's gamma table from its captured original curve.
///
/// Fades are written on each display's display-link tick, one frame per refresh. Which level each
/// frame shows is worked out by a `Fader`. How gamma behaves across processes is in
/// `docs/platform/gamma.md`: the last write wins, and `CGDisplayRestoreColorSyncSettings` undoes
/// only this process's own writes.
///
/// Each table is read back after the last frame of a fade or a single write, and on the 1 Hz tick.
/// A `TableWatch` decides what each read-back means: a reset is re-applied straight away, another
/// app's table on three ticks in a row pauses the display, and another curve on a display at 100%
/// becomes the curve the next dim scales.
@MainActor public final class GammaController: BrightnessBackend {
    /// What the controller knows about one display. Dropped for every display on restore, so the
    /// next write re-captures the original curve and starts a fresh fade from 100%.
    private struct DisplayState {
        /// The display's curve as it was before our first write to it.
        let original: GammaTable

        /// Tells this tracking of the display from earlier ones, so a write or read that lands after
        /// the display was forgotten and tracked again is ignored.
        let generation: Int

        /// Paused while no fade is under way. Nil for a display with no screen to tick with.
        let link: CADisplayLink?

        var fader = Fader()

        /// Decides what each read-back of the display's table means.
        var watch: TableWatch

        /// The time between frames, as the link last reported.
        var refresh = GammaController.assumedRefresh

        /// A refresh the link reported, to find later refreshes from. Refreshes stay in step.
        var knownRefresh: ContinuousClock.Instant?

        /// The next refresh after `time`, or `time` itself if the link hasn't ticked yet.
        func nextRefresh(after time: ContinuousClock.Instant) -> ContinuousClock.Instant {
            guard let knownRefresh else { return time }
            let refreshesSince = ((time - knownRefresh) / refresh).rounded(.up)
            return knownRefresh + refresh * max(refreshesSince, 1)
        }
    }

    /// The time between frames until a display's link reports its own: 60 Hz.
    private nonisolated static let assumedRefresh = Duration.milliseconds(16)

    private var displays: [DisplayID: DisplayState] = [:]

    /// Displays reported paused or unsupported, which get no writes until `resume` or `restore`.
    private var stopped: Set<DisplayID> = []

    /// Each display's first curve captured since launch or the last restore: the curve WindowServer
    /// resets it to when a gamma writer exits. After Resume the original holds another app's
    /// colours, so a reset no longer matches it.
    private var resetCurves: [DisplayID: GammaTable] = [:]

    private var lastGeneration = 0

    public weak var delegate: (any BrightnessBackendDelegate)?

    private let writer = TableWriter()

    public init() {}

    public func apply(_ level: Level, to display: DisplayID, over ramp: Duration) {
        guard !stopped.contains(display), var state = displays[display] ?? startTracking(display) else { return }
        defer { displays[display] = state }
        state.fader.fade(to: level, over: ramp)
        guard state.fader.isFading else { return }
        guard let link = state.link else {
            return write(state.original.scaled(to: state.fader.jump()), to: display, of: state, readBack: true)
        }
        if link.isPaused, !writer.isBusy(display) {
            // A paused link's first tick can be two refreshes away, which would lose the head start
            // of dimming early. Write the first frame now; the link carries on from there.
            writeNextFrame(of: &state, to: display, shownAt: state.nextRefresh(after: .now))
        }
        link.isPaused = !state.fader.isFading
    }

    public func resume(_ display: DisplayID) {
        stopped.remove(display)
        forget(display)  // So the next write captures the curve on screen now as the original.
    }

    public func checkTables() {
        for (display, state) in displays where !state.fader.isFading && !writer.isBusy(display) {
            let level = state.fader.onScreen
            writer.read(display) { [weak self] readBack in
                self?.checked(display, at: level, generation: state.generation, readBack: readBack)
            }
        }
    }

    public func restore() {
        for case let link? in displays.values.map(\.link) { link.invalidate() }
        displays = [:]
        stopped = []
        resetCurves = [:]
        writer.waitForWrites()  // Let queued writes land first, so none lands after the restore.
        CGDisplayRestoreColorSyncSettings()
    }

    /// Captures the display's current curve and creates its display link. Called only before our
    /// first write to the display since launch or the last restore, so our own curve is never
    /// captured as the original. Creating a link can block for tens of milliseconds the first time,
    /// so it happens here rather than in the middle of a fade.
    private func startTracking(_ display: DisplayID) -> DisplayState? {
        guard let original = Self.read(display) else {
            // No table to read, so none to write either.
            stop(display, then: delegate?.displayUnsupported)
            return nil
        }
        let resetCurve = resetCurves[display] ?? original
        resetCurves[display] = resetCurve
        lastGeneration += 1
        return DisplayState(
            original: original, generation: lastGeneration, link: makeLink(for: display),
            watch: TableWatch(original: original, resetCurve: resetCurve))
    }

    /// Stops writing to `display` and forgets it, then tells the delegate through `report`.
    private func stop(_ display: DisplayID, then report: ((DisplayID) -> Void)?) {
        stopped.insert(display)
        forget(display)
        // A frame still waiting would write over the other app's colours. One already being written
        // still lands, once; the other app's next write wins it back.
        writer.cancel(display)
        report?(display)
    }

    private func forget(_ display: DisplayID) {
        displays.removeValue(forKey: display)?.link?.invalidate()
    }

    private func makeLink(for display: DisplayID) -> CADisplayLink? {
        guard let screen = Displays.screen(showing: display) else { return nil }
        let target = LinkTarget { [weak self] link in self?.tick(display, link) }
        let link = screen.displayLink(target: target, selector: #selector(LinkTarget.tick(_:)))
        link.isPaused = true
        link.add(to: .main, forMode: .common)
        return link
    }

    /// Writes the frame for the refresh the link is about to show, and pauses once the fade ends.
    private func tick(_ display: DisplayID, _ link: CADisplayLink) {
        guard var state = displays[display], state.fader.isFading else {
            link.isPaused = true
            return
        }
        // Skip this refresh while the last frame is still being written, rather than replacing it
        // and skipping a level. The fade doesn't advance, so a slow write slows it down instead.
        guard !writer.isBusy(display) else { return }
        let shownAt = ContinuousClock.now + .seconds(link.targetTimestamp - CACurrentMediaTime())
        state.refresh = .seconds(link.targetTimestamp - link.timestamp)
        state.knownRefresh = shownAt
        writeNextFrame(of: &state, to: display, shownAt: shownAt)
        displays[display] = state
        if !state.fader.isFading { link.isPaused = true }
    }

    private func writeNextFrame(of state: inout DisplayState, to display: DisplayID, shownAt: ContinuousClock.Instant) {
        // Nil when this refresh already has its frame, such as the one written as a fade began.
        guard let level = state.fader.nextFrame(shownAt: shownAt, refresh: state.refresh) else { return }
        // Only the fade's last frame is read back: reading every frame would hold each write up,
        // and a read can stall for about 50 ms during an app switch.
        write(state.original.scaled(to: level), to: display, of: state, readBack: !state.fader.isFading)
    }

    private func write(_ table: GammaTable, to display: DisplayID, of state: DisplayState, readBack: Bool) {
        writer.write(table, to: display, readBack: readBack) {
            [weak self, generation = state.generation] time, readBack in
            self?.landed(table, on: display, generation: generation, at: time, readBack: readBack)
        }
    }

    private func landed(
        _ written: GammaTable, on display: DisplayID, generation: Int, at time: ContinuousClock.Instant,
        readBack: GammaTable?
    ) {
        guard var state = displays[display], state.generation == generation else { return }
        state.fader.frameLanded(at: time, refresh: state.refresh)
        let action = readBack.map { state.watch.afterWrite(written, readBack: $0) } ?? .carryOn
        displays[display] = state
        act(on: action, for: display)
    }

    /// A tick's read-back, taken while the display showed `level`. Ignored if the display has been
    /// tracked again or started another fade since it was asked for.
    private func checked(_ display: DisplayID, at level: Level, generation: Int, readBack: GammaTable?) {
        guard let readBack, var state = displays[display], state.generation == generation,
            !state.fader.isFading, state.fader.onScreen == level
        else { return }
        let action =
            level < .full
            ? state.watch.onTick(expecting: state.original.scaled(to: level), readBack: readBack)
            : state.watch.onTickUndimmed(readBack: readBack)
        displays[display] = state
        act(on: action, for: display)
    }

    private func act(on action: TableWatch.Action, for display: DisplayID) {
        switch action {
        case .carryOn:
            break
        case .reapply:
            // macOS reset the table, so this may jump (CODING_STANDARDS.md, No flash). Not read back,
            // so a table that keeps resetting can't loop; the next tick checks it.
            guard let state = displays[display], !state.fader.isFading else { return }
            write(state.original.scaled(to: state.fader.onScreen), to: display, of: state, readBack: false)
        case .recapture:
            // The curve on screen is the one to dim on top of now. A dimmed display was reset by
            // macOS, so it may jump back to its level.
            guard let level = displays[display]?.fader.onScreen else { return }
            forget(display)
            if level < .full { apply(level, to: display, over: .zero) }
        case .pause:
            stop(display, then: delegate?.displayPaused)
        case .unsupported:
            stop(display, then: delegate?.displayUnsupported)
        }
    }

    fileprivate nonisolated static func read(_ display: DisplayID) -> GammaTable? {
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

    fileprivate nonisolated static func write(_ table: GammaTable, to display: DisplayID) {
        _ = CGSetDisplayTransferByTable(
            display.rawValue, UInt32(table.red.count), table.red, table.green, table.blue)
    }
}

/// Writes gamma tables off the main actor, in order, and reads them back. A write can block for up
/// to about 30 ms. While a display's write is waiting, in progress, or not yet reported back as
/// landed, the display is busy. A newer table for a busy display replaces the waiting one, so the
/// newest table is always the one written.
private final class TableWriter: Sendable {
    typealias Landed = @MainActor @Sendable (ContinuousClock.Instant, GammaTable?) -> Void

    private struct Pending {
        let table: GammaTable
        let readBack: Bool
        let landed: Landed
    }

    private struct State {
        var waiting: [DisplayID: Pending] = [:]
        var writing: Set<DisplayID> = []
    }

    private let queue = DispatchQueue(label: "io.github.ravi-03.cathemeral.gamma-writes")
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Whether a write to `display` is waiting, in progress, or not yet reported as landed.
    func isBusy(_ display: DisplayID) -> Bool {
        state.withLock { $0.waiting[display] != nil || $0.writing.contains(display) }
    }

    /// - Parameters:
    ///   - readBack: read the table back straight after writing it.
    ///   - landed: called on the main actor with the time the write finished and, if asked for, the
    ///     table read back, before the display stops being busy.
    func write(_ table: GammaTable, to display: DisplayID, readBack: Bool, landed: @escaping Landed) {
        let alreadyQueued = state.withLock { state in
            defer { state.waiting[display] = Pending(table: table, readBack: readBack, landed: landed) }
            return state.waiting[display] != nil
        }
        guard !alreadyQueued else { return }  // The queued write will pick up this newer table.
        queue.async { [state] in
            let pending = state.withLock { state in
                let pending = state.waiting.removeValue(forKey: display)
                if pending != nil { state.writing.insert(display) }
                return pending
            }
            guard let pending else { return }  // Cancelled.
            GammaController.write(pending.table, to: display)
            let time = ContinuousClock.now
            let readBack = pending.readBack ? GammaController.read(display) : nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated { pending.landed(time, readBack) }
                state.withLock { _ = $0.writing.remove(display) }
            }
        }
    }

    /// Drops the table waiting to be written to `display`, if any. A write already in progress
    /// still lands.
    func cancel(_ display: DisplayID) {
        state.withLock { _ = $0.waiting.removeValue(forKey: display) }
    }

    /// Reads `display`'s table after every write queued so far, and hands it to `then` on the main
    /// actor (nil if it can't be read).
    func read(_ display: DisplayID, then: @escaping @MainActor @Sendable (GammaTable?) -> Void) {
        queue.async {
            let table = GammaController.read(display)
            DispatchQueue.main.async { MainActor.assumeIsolated { then(table) } }
        }
    }

    /// Returns once every write queued so far has landed.
    func waitForWrites() {
        queue.sync {}
    }
}

/// The display link's target. `CADisplayLink` needs an Objective-C object and selector. The link
/// is added to the main run loop, so it ticks on the main actor.
@MainActor private final class LinkTarget: NSObject {
    private let onTick: @MainActor (CADisplayLink) -> Void

    init(onTick: @escaping @MainActor (CADisplayLink) -> Void) {
        self.onTick = onTick
    }

    @objc func tick(_ link: CADisplayLink) {
        onTick(link)
    }
}
