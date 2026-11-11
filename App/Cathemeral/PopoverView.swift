import AppKit
import BrightnessCore
import BrightnessPlatform
import SwiftUI

/// The menu bar popover: the master switch and the gear that opens Settings, one card per display,
/// the other apps with open windows, the default level, launch at login and Quit.
struct PopoverView: View {
    let engine: DimmingEngine
    let openWindows: OpenWindows
    let loginItem: LoginItem
    let openSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 8) {
                MasterSwitch(engine: engine)
                Button(action: openSettings) {
                    Image(systemName: "gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .accessibilityLabel("Settings")
            }
            Divider()
            ForEach(engine.displays, id: \.self) { display in
                DisplayCard(engine: engine, display: display)
                Divider()
            }
            OtherOpenWindows(engine: engine, openWindows: openWindows)
            DefaultLevelSlider(engine: engine)
            Divider()
            HStack {
                LaunchAtLoginToggle(loginItem: loginItem)
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .keyboardShortcut("q")
            }
        }
        .padding(14)
        .frame(width: 300)
    }
}

/// The app's name and the switch that turns all dimming off and back on.
struct MasterSwitch: View {
    let engine: DimmingEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle(isOn: Binding(get: { engine.isEnabled }, set: { engine.setEnabled($0) })) {
                Text("Cathemeral").font(.headline)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            if !engine.isEnabled {
                Text("Off: every display shows its normal colours.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Every other app with windows on screen: its window count, a compact slider and its level, or
/// "Default" in grey if it has no app setting. Its slider only saves the level, which applies the
/// next time the app owns a display.
struct OtherOpenWindows: View {
    let engine: DimmingEngine
    let openWindows: OpenWindows

    var body: some View {
        let others = engine.otherOpenApps(openWindows.apps)
        if !others.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Other open windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(others, id: \.app.id) { open in
                            OpenAppRow(engine: engine, open: open)
                        }
                    }
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
        }
    }
}

/// One app in the list of other open windows.
struct OpenAppRow: View {
    let engine: DimmingEngine
    let open: OpenApp

    var body: some View {
        let level = engine.level(for: open.app.id)
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 0) {
                Text(open.app.name).lineLimit(1).truncationMode(.tail)
                Text(open.windowCount == 1 ? "1 window" : "\(open.windowCount) windows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Slider(
                value: Binding(get: { level.fraction }, set: { engine.setLevel(Level($0), for: open.app.id) }),
                in: Level.floor...1.0
            )
            .controlSize(.mini)
            .frame(width: 90)
            Group {
                if engine.hasAppSetting(for: open.app.id) {
                    Text(level.description)
                } else {
                    Text("Default").foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            .frame(width: 48, alignment: .trailing)
        }
    }
}

/// Registers and unregisters the login item.
struct LaunchAtLoginToggle: View {
    let loginItem: LoginItem

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Toggle("Launch at login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
                .toggleStyle(.checkbox)
            if loginItem.needsApproval {
                Button("Allow in System Settings") { loginItem.openSystemSettings() }
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }
}

/// A display, its display owner and the owner's level, or why the display isn't being dimmed.
struct DisplayCard: View {
    let engine: DimmingEngine
    let display: DisplayID

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(Displays.name(of: display))
                .font(.caption)
                .foregroundStyle(.secondary)
            switch engine.status(of: display) {
            case .paused:
                Text("Another app is controlling this display's colours")
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Resume") { engine.resume(display) }
                    .controlSize(.small)
            case .unsupported:
                Text("Unsupported").font(.headline)
                Text("Dimming doesn't work on this display.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .dimming:
                OwnerLevel(engine: engine, display: display)
            }
        }
    }
}

/// The display owner and its level, or "Not dimmed" for an unowned display.
struct OwnerLevel: View {
    let engine: DimmingEngine
    let display: DisplayID

    var body: some View {
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
