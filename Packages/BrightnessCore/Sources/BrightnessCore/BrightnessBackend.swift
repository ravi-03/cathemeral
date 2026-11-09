/// The only thing that touches the screen. The engine decides levels; the backend shows them.
///
/// Today the gamma controller is the only backend (ADR 0001). The protocol stays so a per-window
/// overlay backend can be added later.
@MainActor public protocol BrightnessBackend: AnyObject {
    /// Shows `level` on `display`. The level is already clamped to the floor.
    func apply(_ level: Level, to display: DisplayID)

    /// Puts every display back to its original curve.
    func restore()
}
