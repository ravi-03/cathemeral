/// What a global hotkey does. None is bound until the user chooses one in Settings.
public enum HotkeyAction: String, CaseIterable, Sendable {
    /// Steps the frontmost app's level up by 10%.
    case levelUp
    /// Steps the frontmost app's level down by 10%.
    case levelDown
    /// Turns the master switch on or off.
    case toggleMasterSwitch
}

/// A key and the modifiers held with it, as the user recorded it.
public struct Hotkey: Hashable, Sendable {
    /// The virtual key code, as macOS reports it for a key-down event.
    public let keyCode: UInt16
    public let modifiers: Modifiers

    public init(keyCode: UInt16, modifiers: Modifiers) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    /// The modifier keys held with the key.
    public struct Modifiers: OptionSet, Hashable, Sendable {
        public let rawValue: Int

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1 << 0)
        public static let option = Modifiers(rawValue: 1 << 1)
        public static let control = Modifiers(rawValue: 1 << 2)
        public static let shift = Modifiers(rawValue: 1 << 3)
    }
}
