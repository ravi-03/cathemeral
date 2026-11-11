import AppKit
import BrightnessCore
import BrightnessPlatform
import Carbon.HIToolbox
import SwiftUI

/// Keeps the user's global hotkeys registered and acts on each press. A level hotkey steps the
/// frontmost app's level and shows the indicator on its display; the on/off hotkey flips the master
/// switch.
@MainActor @Observable final class Hotkeys {
    @ObservationIgnored private let engine: DimmingEngine
    @ObservationIgnored private lazy var service = HotkeyService { [weak self] action in self?.pressed(action) }
    @ObservationIgnored private let indicator = HotkeyIndicator()

    /// The action whose hotkey the Settings window is recording, if any. While one records, no hotkey
    /// is registered, so pressing one that is already bound reaches the recorder instead of acting.
    var recording: HotkeyAction? {
        didSet { if (recording == nil) != (oldValue == nil) { register(engine.hotkeys) } }
    }

    /// The actions whose hotkey macOS refused, usually because another app holds it.
    private(set) var refused: Set<HotkeyAction> = []

    init(engine: DimmingEngine) {
        self.engine = engine
    }

    /// Registers the bound hotkeys, and registers them again whenever the bindings change.
    func start() {
        let bindings = withObservationTracking {
            engine.hotkeys
        } onChange: { [weak self] in
            // Called before the change lands, so look again once it has.
            Task { @MainActor in self?.start() }
        }
        register(bindings)
    }

    func stop() {
        service.unregisterAll()
    }

    private func register(_ bindings: [HotkeyAction: Hotkey]) {
        refused = service.register(recording == nil ? bindings : [:])
    }

    private func pressed(_ action: HotkeyAction) {
        switch action {
        case .toggleMasterSwitch:
            engine.setEnabled(!engine.isEnabled)
        case .levelUp, .levelDown:
            guard
                let (app, frontWindowDisplay) = Displays.frontmostApp(),
                let level = engine.nudgeLevel(of: app, action == .levelUp ? .up : .down)
            else { return }
            // The display that changed: the one with the app's front window if the app owns it, else
            // any it owns. An app that owns none only saved its level, so show it where its window is.
            let owned = engine.displays.filter { engine.owner(of: $0)?.id == app.id }
            let display = owned.contains(frontWindowDisplay) ? frontWindowDisplay : owned.first ?? frontWindowDisplay
            indicator.show("\(app.name) \(level)", on: display)
        }
    }
}

/// The small "Notion 40%" panel a level hotkey shows for a second, near the bottom of the display
/// it changed. It never takes focus or clicks.
@MainActor final class HotkeyIndicator {
    /// How long the indicator stays up after the last press.
    private static let shownFor = Duration.seconds(1)

    private var panel: NSPanel?
    private var hide: Task<Void, Never>?

    func show(_ text: String, on display: DisplayID) {
        guard let screen = Displays.screen(showing: display) else { return }
        let panel = panel ?? makePanel()
        self.panel = panel
        let hosting = NSHostingView(rootView: IndicatorView(text: text))
        panel.contentView = hosting
        let size = hosting.fittingSize
        let frame = screen.visibleFrame
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.minY + frame.height * 0.12)
        panel.setFrame(NSRect(origin: origin, size: size), display: true)
        panel.alphaValue = 1
        panel.orderFrontRegardless()

        hide?.cancel()
        hide = Task { [weak panel] in
            try? await Task.sleep(for: Self.shownFor)
            guard !Task.isCancelled, let panel else { return }
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.2
                panel.animator().alphaValue = 0
            }
            if !Task.isCancelled { panel.orderOut(nil) }
        }
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        return panel
    }
}

private struct IndicatorView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 17, weight: .medium))
            .monospacedDigit()
            .padding(.horizontal, 18)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: Capsule())
            .padding(8)
    }
}

/// The hotkey bindings in the Settings window: one row per action, each with a recorder and a
/// clear button.
struct HotkeySettings: View {
    let engine: DimmingEngine
    let hotkeys: Hotkeys

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hotkeys").font(.headline)
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(HotkeyAction.allCases, id: \.self) { action in
                    GridRow {
                        Text(action.title)
                        HotkeyRecorder(engine: engine, hotkeys: hotkeys, action: action)
                    }
                }
            }
            Text("Each needs ⌘ or ⌃. Level hotkeys change the app in front by 10%.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

extension HotkeyAction {
    fileprivate var title: String {
        switch self {
        case .levelUp: "Level up"
        case .levelDown: "Level down"
        case .toggleMasterSwitch: "Turn on or off"
        }
    }
}

/// A button showing an action's hotkey. Clicked, it waits for the next key combination: Escape
/// cancels, and a combination without ⌘ or ⌃ is refused.
private struct HotkeyRecorder: View {
    let engine: DimmingEngine
    let hotkeys: Hotkeys
    let action: HotkeyAction
    @State private var monitor: Any?
    @State private var refusedCombo = false

    private var isRecording: Bool { monitor != nil && hotkeys.recording == action }

    var body: some View {
        HStack(spacing: 4) {
            Button(action: toggleRecording) {
                Text(label)
                    .monospacedDigit()
                    .frame(minWidth: 120)
            }
            .help(isRecording ? "Press a key combination, or Escape to cancel" : "Click to record a hotkey")
            if engine.hotkeys[action] != nil, !isRecording {
                Button {
                    engine.setHotkey(nil, for: action)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("Clear")
                .accessibilityLabel("Clear the \(action.title) hotkey")
            }
            if hotkeys.refused.contains(action), !isRecording {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .help("macOS refused this hotkey. Another app may already use it.")
            }
        }
        .onDisappear(perform: stopRecording)
        // Another recorder started, so this one stops listening.
        .onChange(of: hotkeys.recording) { _, recording in
            if recording != action { removeMonitor() }
        }
    }

    private var label: String {
        if isRecording { return refusedCombo ? "Add ⌘ or ⌃…" : "Type hotkey…" }
        return engine.hotkeys[action]?.displayName ?? "Record"
    }

    private func toggleRecording() {
        if isRecording { stopRecording() } else { startRecording() }
    }

    private func startRecording() {
        refusedCombo = false
        hotkeys.recording = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == kVK_Escape, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                stopRecording()  // Escape on its own.
                return nil
            }
            guard let hotkey = Hotkey(event: event), hotkey.isAllowed else {
                refusedCombo = true
                return nil
            }
            engine.setHotkey(hotkey, for: action)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        guard monitor != nil else { return }
        removeMonitor()
        if hotkeys.recording == action { hotkeys.recording = nil }
    }

    private func removeMonitor() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
    }
}
