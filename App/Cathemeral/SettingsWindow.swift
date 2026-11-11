import AppKit
import BrightnessCore
import BrightnessPlatform
import SwiftUI

/// The Settings window, opened from the popover's gear and the right-click menu: the default level
/// and launch at login, the hotkeys, the Apps list, and the steps for a screen stuck dim.
@MainActor final class SettingsWindow {
    private let engine: DimmingEngine
    private let loginItem: LoginItem
    private let hotkeys: Hotkeys
    private let installedApps = InstalledApps()
    private var window: NSWindow?

    init(engine: DimmingEngine, loginItem: LoginItem, hotkeys: Hotkeys) {
        self.engine = engine
        self.loginItem = loginItem
        self.hotkeys = hotkeys
    }

    /// Brings the window to the front, making it on first use. Apps are looked up again each time,
    /// to catch any installed or removed since.
    func show() {
        loginItem.refresh()
        installedApps.forget()
        if let hosting = window?.contentViewController as? NSHostingController<SettingsView> {
            hosting.rootView = settingsView()
        }
        let window = window ?? makeWindow()
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func settingsView() -> SettingsView {
        SettingsView(engine: engine, loginItem: loginItem, hotkeys: hotkeys, installedApps: installedApps)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(contentViewController: NSHostingController(rootView: settingsView()))
        window.title = "Cathemeral Settings"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

struct SettingsView: View {
    let engine: DimmingEngine
    let loginItem: LoginItem
    let hotkeys: Hotkeys
    let installedApps: InstalledApps

    var body: some View {
        TabView {
            VStack(alignment: .leading, spacing: 14) {
                DefaultLevelSlider(engine: engine)
                LaunchAtLoginToggle(loginItem: loginItem)
                Divider()
                HotkeySettings(engine: engine, hotkeys: hotkeys)
                Spacer()
            }
            .padding(20)
            .tabItem { Label("General", systemImage: "gearshape") }

            AppsList(engine: engine, installedApps: installedApps)
                .tabItem { Label("Apps", systemImage: "square.grid.2x2") }

            RecoveryStepsView()
                .padding(20)
                .tabItem { Label("Stuck Dim?", systemImage: "lifepreserver") }
        }
        .padding(12)
        .frame(width: 460, height: 380)
    }
}

/// Every saved app setting, sorted by name, including apps that aren't running. Each row's slider
/// behaves like any other: live if its app owns a display, otherwise it only saves. Remove is
/// "Use default".
struct AppsList: View {
    let engine: DimmingEngine
    let installedApps: InstalledApps

    var body: some View {
        let apps = engine.savedApps(installedName: installedApps.name(of:))
        if apps.isEmpty {
            VStack(spacing: 6) {
                Text("No app settings yet").font(.headline)
                Text("Set a level for an app from the menu bar, and it appears here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(apps, id: \.id) { app in
                SavedAppRow(engine: engine, app: app, icon: installedApps.icon(of: app.id))
            }
        }
    }
}

/// One app in the Apps list. An app that is no longer installed is greyed out.
struct SavedAppRow: View {
    let engine: DimmingEngine
    let app: SavedApp
    let icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle))
                .resizable()
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(app.name).lineLimit(1).truncationMode(.middle)
                if !app.isInstalled {
                    Text("Not installed").font(.caption)
                }
            }
            .help(app.id.rawValue)
            Spacer(minLength: 4)
            Slider(
                value: Binding(get: { app.level.fraction }, set: { engine.setLevel(Level($0), for: app.id) }),
                in: Level.floor...1.0
            )
            .controlSize(.small)
            .frame(width: 130)
            Text(app.level.description)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            Button {
                engine.useDefault(for: app.id)
            } label: {
                Image(systemName: "minus.circle")
            }
            .buttonStyle(.borderless)
            .help("Remove, so the app uses the default level")
            .accessibilityLabel("Remove \(app.name)")
        }
        .opacity(app.isInstalled ? 1 : 0.5)
    }
}

/// How to get a screen stuck dim back to normal without the app, as in the README.
struct RecoveryStepsView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(RecoverySteps.title).font(.headline)
            Text(RecoverySteps.intro)
            ForEach(Array(RecoverySteps.steps.enumerated()), id: \.offset) { number, step in
                Text("\(number + 1). ") + Text("\(step.title):").bold() + Text(" \(step.detail)")
            }
            Text(RecoverySteps.footer).foregroundStyle(.secondary)
            Spacer()
        }
        .fixedSize(horizontal: false, vertical: true)
        .textSelection(.enabled)
    }
}
