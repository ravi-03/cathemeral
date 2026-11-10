/// The engine's sense of time, injected so tests can control it.
@MainActor public protocol DimmingClock: AnyObject {
    var now: ContinuousClock.Instant { get }

    /// Runs `action` on the main actor once `delay` has passed, unless it is cancelled first.
    func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction
}

/// An action waiting on a `DimmingClock`.
@MainActor public protocol ScheduledAction: AnyObject {
    /// Stops the action from running. Does nothing if it already ran.
    func cancel()
}

/// The real clock.
public final class SystemClock: DimmingClock {
    public init() {}

    public var now: ContinuousClock.Instant { .now }

    public func schedule(after delay: Duration, _ action: @escaping @MainActor () -> Void) -> any ScheduledAction {
        SleepingTask(
            Task { @MainActor in
                // Checked again after the sleep: a cancel can land while the task waits to resume.
                guard (try? await Task.sleep(for: delay)) != nil, !Task.isCancelled else { return }
                action()
            })
    }

    private final class SleepingTask: ScheduledAction {
        private let task: Task<Void, Never>

        init(_ task: Task<Void, Never>) {
            self.task = task
        }

        func cancel() { task.cancel() }
    }
}
