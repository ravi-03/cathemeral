import AppKit
import BrightnessCore
import BrightnessPlatform
import SwiftUI

/// The menu bar popover: one card per display, the default level, and Quit.
struct PopoverView: View {
    let engine: DimmingEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(engine.displays, id: \.self) { display in
                DisplayCard(engine: engine, display: display)
                Divider()
            }
            DefaultLevelSlider(engine: engine)
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
            Text(Displays.name(of: display))
                .font(.caption)
                .foregroundStyle(.secondary)
            if let owner = engine.owner(of: display) {
                LevelSlider(level: engine.level(for: owner.id)) {
                    engine.setLevel($0, for: owner.id)
                } title: {
                    Text(owner.name).font(.headline)
                }
                if engine.hasAppSetting(for: owner.id) {
                    Button("Use default") { engine.useDefault(for: owner.id) }
                        .controlSize(.small)
                } else {
                    Text("Using default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Text("Not dimmed").font(.headline)
            }
        }
    }
}

/// The default level, for every app without its own app setting.
struct DefaultLevelSlider: View {
    let engine: DimmingEngine

    var body: some View {
        LevelSlider(level: engine.defaultLevel, set: engine.setDefaultLevel) {
            Text("Default for new apps")
        }
    }
}

/// A title and level on one row, and a slider from the floor to 100% under them.
struct LevelSlider<Title: View>: View {
    let level: Level
    let set: (Level) -> Void
    @ViewBuilder let title: Title

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                title
                Spacer()
                Text(level.description).monospacedDigit()
            }
            Slider(
                value: Binding(get: { level.fraction }, set: { set(Level($0)) }),
                in: Level.floor...1.0
            )
        }
    }
}
