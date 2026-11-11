import AppKit
import BrightnessCore
import SwiftUI

/// The Settings window, opened from the right-click menu. For now it holds the default level and
/// launch at login. Ticket 11 adds the Apps list and the recovery steps.
@MainActor final class SettingsWindow {
    private let engine: DimmingEngine
    private let loginItem: LoginItem
    private var window: NSWindow?

    init(engine: DimmingEngine, loginItem: LoginItem) {
        self.engine = engine
        self.loginItem = loginItem
    }

    /// Brings the window to the front, making it on first use.
    func show() {
        let window = window ?? makeWindow()
        self.window = window
        loginItem.refresh()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentViewController: NSHostingController(rootView: SettingsView(engine: engine, loginItem: loginItem)))
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            DefaultLevelSlider(engine: engine)
            LaunchAtLoginToggle(loginItem: loginItem)
        }
        .padding(20)
        .frame(width: 360)
    }
}
