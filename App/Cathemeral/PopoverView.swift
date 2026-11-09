import AppKit
import BrightnessCore
import SwiftUI

/// The menu bar popover: one card for the built-in display, and Quit.
struct PopoverView: View {
    let engine: DimmingEngine
    let display: DisplayID

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DisplayCard(engine: engine, display: display)
            Divider()
            Button("Quit Cathemeral") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// A display, its display owner and the owner's level.
struct DisplayCard: View {
    let engine: DimmingEngine
    let display: DisplayID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Built-in Display")
                .font(.caption)
                .foregroundStyle(.secondary)
            if let owner = engine.owner(of: display) {
                let level = engine.level(for: owner.id)
                HStack {
                    Text(owner.name).font(.headline)
                    Spacer()
                    Text(level.description).monospacedDigit()
                }
                Slider(
                    value: Binding(
                        get: { level.fraction },
                        set: { engine.setLevel(Level($0), for: owner.id) }
                    ),
                    in: Level.floor...1.0
                )
            } else {
                Text("Not dimmed").font(.headline)
            }
        }
    }
}
