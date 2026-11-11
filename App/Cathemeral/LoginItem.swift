import Observation
import ServiceManagement
import os

/// Launch at login, through the app's login item.
@MainActor @Observable final class LoginItem {
    /// Whether the app launches at login.
    private(set) var isEnabled = false

    /// The user turned launch at login on, but must still allow it in System Settings.
    private(set) var needsApproval = false

    init() {
        refresh()
    }

    /// Registers or unregisters the login item.
    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Couldn't \(enabled ? "register" : "unregister", privacy: .public) the login item: \(error)")
        }
        refresh()
    }

    /// Reads the login item's status again, since the user can change it in System Settings.
    func refresh() {
        let status = SMAppService.mainApp.status
        isEnabled = status == .enabled
        needsApproval = status == .requiresApproval
    }

    func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

private let logger = Logger(subsystem: "io.github.ravi-03.cathemeral", category: "login-item")
