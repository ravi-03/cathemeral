/// How to get a screen stuck dim back to normal without the app, shown in Settings. The README's
/// section of the same title says the same, and a test keeps the two matching.
public enum RecoverySteps {
    public struct Step: Hashable, Sendable {
        public let title: String
        public let detail: String
    }

    public static let title = "If your screen is stuck dim"

    public static let intro =
        "The dimming lives only in memory, so a restart always clears it. The 10% floor keeps the screen readable enough for these steps, fastest first:"

    public static let steps = [
        Step(title: "Quit the app", detail: "menu bar icon → Quit, or ⌥⌘Esc → Cathemeral → Force Quit."),
        Step(
            title: "Reload the colour profile",
            detail: "System Settings → Displays → Color profile. Pick another profile, then the original again."),
        Step(
            title: "Sleep and wake the display",
            detail: "close and open the lid, or unplug and replug the external monitor."),
        Step(title: "Log out or restart", detail: "always works."),
    ]

    public static let footer =
        "The brightness keys, Night Shift and True Tone won't fix it, because they don't touch the gamma table."
}

extension RecoverySteps.Step: CustomStringConvertible {
    /// The step as one line, as the README writes it without emphasis.
    public var description: String { "\(title): \(detail)" }
}
