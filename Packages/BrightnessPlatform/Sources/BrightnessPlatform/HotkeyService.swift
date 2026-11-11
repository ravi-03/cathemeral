import AppKit
import BrightnessCore
import Carbon.HIToolbox
import os

/// Registers the user's global hotkeys and reports each press.
///
/// Uses Carbon's `RegisterEventHotKey`, which needs no Accessibility or Input Monitoring permission:
/// macOS delivers only the registered key combinations, never other keystrokes. Since macOS 15 it
/// refuses a combination whose only modifiers are Option or Option-Shift, so the recorder requires
/// Command or Control (`Hotkey.isAllowed`).
@MainActor public final class HotkeyService {
    /// Tags our hotkeys in Carbon events: "CTHM".
    private static let signature: OSType = 0x4354_484D

    private let onPress: @MainActor (HotkeyAction) -> Void
    private var registered: [HotkeyAction: EventHotKeyRef] = [:]
    private var handler: EventHandlerRef?

    /// - Parameter onPress: a bound hotkey was pressed.
    public init(onPress: @escaping @MainActor (HotkeyAction) -> Void) {
        self.onPress = onPress
    }

    /// Replaces every registered hotkey with `hotkeys`. Pass an empty dictionary to unbind them all,
    /// such as while the user records a new one.
    ///
    /// - Returns: the actions whose hotkey macOS refused, usually because another app holds it.
    @discardableResult public func register(_ hotkeys: [HotkeyAction: Hotkey]) -> Set<HotkeyAction> {
        unregisterAll()
        guard !hotkeys.isEmpty else { return [] }
        installHandlerIfNeeded()
        var refused: Set<HotkeyAction> = []
        for (action, hotkey) in hotkeys {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: Self.carbonID(for: action))
            let status = RegisterEventHotKey(
                UInt32(hotkey.keyCode), hotkey.carbonModifiers, id, GetEventDispatcherTarget(), 0, &ref)
            if status == noErr, let ref {
                registered[action] = ref
            } else {
                logger.error("Couldn't register the \(action.rawValue, privacy: .public) hotkey: \(status)")
                refused.insert(action)
            }
        }
        return refused
    }

    public func unregisterAll() {
        for ref in registered.values { UnregisterEventHotKey(ref) }
        registered = [:]
    }

    private func installHandlerIfNeeded() {
        guard handler == nil else { return }
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The callback can't capture, so it finds this service through `userData`. The service lives
        // as long as the app, so the unretained pointer stays valid.
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, event, userData in
                guard let event, let userData else { return OSStatus(eventNotHandledErr) }
                var id = EventHotKeyID()
                let status = GetEventParameter(
                    event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil,
                    MemoryLayout<EventHotKeyID>.size, nil, &id)
                guard status == noErr, id.signature == HotkeyService.signature else {
                    return OSStatus(eventNotHandledErr)
                }
                let number = id.id
                // Carbon dispatches hotkey events on the main thread.
                MainActor.assumeIsolated {
                    let service = Unmanaged<HotkeyService>.fromOpaque(userData).takeUnretainedValue()
                    if let action = HotkeyAction.allCases.first(where: { HotkeyService.carbonID(for: $0) == number }) {
                        service.onPress(action)
                    }
                }
                return noErr
            }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), &handler)
        if status != noErr {
            logger.error("Couldn't install the hotkey handler: \(status)")
        }
    }

    /// The ID Carbon reports a press under: the action's place in `allCases`, from 1. Never saved, so
    /// reordering the cases is safe.
    private nonisolated static func carbonID(for action: HotkeyAction) -> UInt32 {
        UInt32(HotkeyAction.allCases.firstIndex(of: action)! + 1)
    }
}

extension Hotkey {
    /// The hotkey for a key-down event, or nil if no modifier is held.
    public init?(event: NSEvent) {
        var modifiers: Modifiers = []
        let flags = event.modifierFlags
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.option) { modifiers.insert(.option) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.shift) { modifiers.insert(.shift) }
        guard !modifiers.isEmpty else { return nil }
        self.init(keyCode: event.keyCode, modifiers: modifiers)
    }

    /// Whether macOS will register it: it needs Command or Control, since macOS 15 refuses hotkeys
    /// whose only modifiers are Option or Option-Shift, and a bare Shift would take over typing.
    public var isAllowed: Bool {
        modifiers.contains(.command) || modifiers.contains(.control)
    }

    /// How macOS menus write it, such as "⌃⌥↓".
    @MainActor public var displayName: String {
        var name = ""
        if modifiers.contains(.control) { name += "⌃" }
        if modifiers.contains(.option) { name += "⌥" }
        if modifiers.contains(.shift) { name += "⇧" }
        if modifiers.contains(.command) { name += "⌘" }
        return name + Self.keyName(keyCode)
    }

    fileprivate var carbonModifiers: UInt32 {
        var flags = 0
        if modifiers.contains(.command) { flags |= cmdKey }
        if modifiers.contains(.option) { flags |= optionKey }
        if modifiers.contains(.control) { flags |= controlKey }
        if modifiers.contains(.shift) { flags |= shiftKey }
        return UInt32(flags)
    }

    private static let specialKeys: [Int: String] = [
        kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_LeftArrow: "←", kVK_RightArrow: "→",
        kVK_Return: "↩", kVK_Tab: "⇥", kVK_Space: "Space", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
        kVK_Escape: "⎋", kVK_Home: "↖", kVK_End: "↘", kVK_PageUp: "⇞", kVK_PageDown: "⇟",
        kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
        kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        kVK_F13: "F13", kVK_F14: "F14", kVK_F15: "F15", kVK_F16: "F16", kVK_F17: "F17", kVK_F18: "F18",
        kVK_F19: "F19", kVK_F20: "F20",
    ]

    /// The key's name: a symbol for special keys, otherwise the character it types on the current
    /// keyboard layout, so "Z" on a German layout is the key that types Z there.
    @MainActor private static func keyName(_ keyCode: UInt16) -> String {
        if let special = specialKeys[Int(keyCode)] { return special }
        guard
            let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
            let layoutData = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return "Key \(keyCode)" }
        let layout = Unmanaged<CFData>.fromOpaque(layoutData).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var characters = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = layout.withUnsafeBytes { bytes in
            UCKeyTranslate(
                bytes.baseAddress!.assumingMemoryBound(to: UCKeyboardLayout.self), keyCode,
                UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeys, characters.count, &length, &characters)
        }
        guard status == noErr, length > 0 else { return "Key \(keyCode)" }
        return String(utf16CodeUnits: characters, count: length).uppercased()
    }
}

private let logger = Logger(subsystem: "io.github.ravi-03.cathemeral", category: "hotkeys")
