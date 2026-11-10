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
@MainActor public final class GammaController: BrightnessBackend {
    /// What the controller knows about one display. Dropped for every display on restore, so the
    /// next write re-captures the original curve and starts a fresh fade from 100%.
    private struct DisplayState {
        /// The display's curve as it was before our first write to it.
        let original: GammaTable

        /// Paused while no fade is under way. Nil for a display with no screen to tick with.
        let link: CADisplayLink?

        var fader = Fader()

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

    private let writer = TableWriter()

    public init() {}

    public func apply(_ level: Level, to display: DisplayID, over ramp: Duration) {
        guard var state = displays[display] ?? startTracking(display) else { return }
        defer { displays[display] = state }
        state.fader.fade(to: level, over: ramp)
        guard state.fader.isFading else { return }
        guard let link = state.link else {
            return writer.write(state.original.scaled(to: state.fader.jump()), to: display)
        }
        if link.isPaused, !writer.isBusy(display) {
            // A paused link's first tick can be two refreshes away, which would lose the head start
            // of dimming early. Write the first frame now; the link carries on from there.
            writeNextFrame(of: &state, to: display, shownAt: state.nextRefresh(after: .now))
        }
        link.isPaused = !state.fader.isFading
    }

    public func restore() {
        for case let link? in displays.values.map(\.link) { link.invalidate() }
        displays = [:]
        writer.waitForWrites()  // Let queued writes land first, so none lands after the restore.
        CGDisplayRestoreColorSyncSettings()
    }

    /// Captures the display's current curve and creates its display link. Called only before our
    /// first write to the display since launch or the last restore, so our own curve is never
    /// captured as the original. Creating a link can block for tens of milliseconds the first time,
    /// so it happens here rather than in the middle of a fade.
    private func startTracking(_ display: DisplayID) -> DisplayState? {
        guard let original = Self.read(display) else { return nil }
        return DisplayState(original: original, link: makeLink(for: display))
    }

    private func makeLink(for display: DisplayID) -> CADisplayLink? {
        guard let screen = NSScreen.screens.first(where: { $0.displayID == display }) else { return nil }
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
        writer.write(state.original.scaled(to: level), to: display) { [weak self] landed in
            guard var state = self?.displays[display] else { return }
            state.fader.frameLanded(at: landed, refresh: state.refresh)
            self?.displays[display] = state
        }
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

    fileprivate nonisolated static func write(_ table: GammaTable, to display: DisplayID) {
        _ = CGSetDisplayTransferByTable(
            display.rawValue, UInt32(table.red.count), table.red, table.green, table.blue)
    }
}

/// Writes gamma tables off the main actor, in order. A write can block for up to about 30 ms.
/// While a display's write is waiting, in progress, or not yet reported back as landed, the display
/// is busy. A newer table for a busy display replaces the waiting one, so the newest table is
/// always the one written.
private final class TableWriter: Sendable {
    private struct State {
        var waiting: [DisplayID: GammaTable] = [:]
        var writing: Set<DisplayID> = []
    }

    private let queue = DispatchQueue(label: "io.github.ravi-03.cathemeral.gamma-writes")
    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Whether a write to `display` is waiting, in progress, or not yet reported as landed.
    func isBusy(_ display: DisplayID) -> Bool {
        state.withLock { $0.waiting[display] != nil || $0.writing.contains(display) }
    }

    /// - Parameter landed: called on the main actor with the time the write finished, before the
    ///   display stops being busy.
    func write(
        _ table: GammaTable, to display: DisplayID,
        landed: (@MainActor @Sendable (ContinuousClock.Instant) -> Void)? = nil
    ) {
        let alreadyQueued = state.withLock { state in
            defer { state.waiting[display] = table }
            return state.waiting[display] != nil
        }
        guard !alreadyQueued else { return }  // The queued write will pick up this newer table.
        queue.async { [state] in
            let table = state.withLock { state in
                let table = state.waiting.removeValue(forKey: display)
                if table != nil { state.writing.insert(display) }
                return table
            }
            guard let table else { return }
            GammaController.write(table, to: display)
            let time = ContinuousClock.now
            DispatchQueue.main.async {
                MainActor.assumeIsolated { landed?(time) }
                state.withLock { _ = $0.writing.remove(display) }
            }
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

extension NSScreen {
    /// The CoreGraphics display this screen shows.
    fileprivate var displayID: DisplayID? {
        (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber).map { DisplayID($0.uint32Value) }
    }
}
