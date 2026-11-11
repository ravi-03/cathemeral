/// The only thing that touches the screen. The engine decides levels; the backend shows them.
///
/// Today the gamma controller is the only backend (ADR 0001). The protocol stays so a per-window
/// overlay backend can be added later.
@MainActor public protocol BrightnessBackend: AnyObject {
    /// Told when a display stops taking levels. The engine sets itself as the delegate.
    var delegate: (any BrightnessBackendDelegate)? { get set }

    /// Shows `level` on `display`, fading to it over `ramp` with an ease-out curve. A zero ramp
    /// applies it straight away. A new level arriving mid-ramp fades on from the level on screen.
    /// The level is already clamped to the floor. Does nothing on a display reported paused or
    /// unsupported, until `resume` or `restore`.
    func apply(_ level: Level, to display: DisplayID, over ramp: Duration)

    /// Starts showing levels on a paused or unsupported display again. Its current curve is
    /// captured as its original, so the next level dims on top of whatever is on screen now.
    func resume(_ display: DisplayID)

    /// Reads back every display's table, on the 1 Hz window tick. On a dimmed display, a table reset
    /// to the original is re-applied, and another app's table counts toward pausing the display. On
    /// a display at 100%, another curve becomes the one the next level dims.
    func checkTables()

    /// Puts every display back to its original curve, and forgets which displays were paused or
    /// unsupported.
    func restore()
}

/// Hears from the backend about displays that stop taking levels. The backend stops writing to
/// such a display before telling its delegate.
@MainActor public protocol BrightnessBackendDelegate: AnyObject {
    /// Another app has taken over the display's colours (`CONTEXT.md`, paused display).
    func displayPaused(_ display: DisplayID)

    /// Levels don't take on the display, as on some HDR, Sidecar or AirPlay displays.
    func displayUnsupported(_ display: DisplayID)
}
