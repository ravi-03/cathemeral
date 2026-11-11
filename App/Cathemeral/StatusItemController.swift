import AppKit
import BrightnessCore
import BrightnessPlatform
import SwiftUI

/// The menu bar icon. A click opens the popover, and a right-click (or Control-click) opens the
/// quick menu: Enable/Disable, Settings and Quit. Settings also opens from the popover's gear.
///
/// The popover's list of other open windows is read while the popover is open, and never while
/// it's closed.
@MainActor final class StatusItemController: NSObject, NSPopoverDelegate {
    private let engine: DimmingEngine
    private let loginItem: LoginItem
    private let openSettings: () -> Void
    private let openWindows = OpenWindows()
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private let popover = NSPopover()
    private lazy var inventory = WindowInventory { [openWindows] apps in openWindows.apps = apps }

    init(engine: DimmingEngine, loginItem: LoginItem, openSettings: @escaping () -> Void) {
        self.engine = engine
        self.loginItem = loginItem
        self.openSettings = openSettings
        super.init()

        let content = NSHostingController(
            rootView: PopoverView(engine: engine, openWindows: openWindows, loginItem: loginItem) { [weak self] in
                self?.showSettings()
            })
        // The popover grows and shrinks with the list of other open windows.
        content.sizingOptions = .preferredContentSize
        popover.contentViewController = content
        popover.behavior = .transient
        popover.delegate = self

        if let button = statusItem.button {
            button.target = self
            button.action = #selector(clicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        updateIcon()
    }

    @objc private func clicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            showMenu()
        } else {
            togglePopover()
        }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        popover.performClose(nil)
        let menu = NSMenu()
        let toggle = NSMenuItem(
            title: engine.isEnabled ? "Disable Cathemeral" : "Enable Cathemeral", action: #selector(toggleEnabled),
            keyEquivalent: "")
        let settings = NSMenuItem(title: "Settings…", action: #selector(showSettings), keyEquivalent: ",")
        let quit = NSMenuItem(title: "Quit Cathemeral", action: #selector(quit), keyEquivalent: "q")
        for item in [toggle, settings, quit] { item.target = self }
        menu.items = [toggle, settings, .separator(), quit]
        // The menu shows for the length of this click, then the button goes back to opening the popover.
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleEnabled() { engine.setEnabled(!engine.isEnabled) }

    @objc private func showSettings() {
        popover.performClose(nil)
        openSettings()
    }

    @objc private func quit() { NSApp.terminate(nil) }

    func popoverWillShow(_ notification: Notification) {
        loginItem.refresh()
        inventory.start()
    }

    func popoverDidClose(_ notification: Notification) {
        inventory.stop()
    }

    /// Redraws the icon now and whenever the engine's state changes.
    private func updateIcon() {
        let (state, paused) = withObservationTracking {
            (engine.dimmingState, engine.hasPausedDisplay)
        } onChange: { [weak self] in
            // Called before the change lands, so look again once it has.
            Task { @MainActor in self?.updateIcon() }
        }
        statusItem.button?.image = StatusIcon.image(for: state, withDot: paused)
    }
}

/// The apps with windows on screen, as last read by the `WindowInventory`.
@MainActor @Observable final class OpenWindows {
    var apps: [OpenApp] = []
}

/// Draws the menu bar icon: a sun outline when nothing is dimmed, a half-filled sun when a display
/// is dimmed, and a sun with a slash when the master switch is off. A dot in the corner means a display is
/// paused.
///
/// A template image, so it follows the menu bar's colour.
enum StatusIcon {
    static func image(for state: DimmingState, withDot: Bool) -> NSImage {
        let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .regular)
        let symbol = state == .dimmed ? "sun.lefthalf.filled" : "sun.max"
        guard
            let sun = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(configuration)
        else { return NSImage() }
        let image = NSImage(size: sun.size, flipped: false) { bounds in
            sun.draw(in: bounds)
            // There is no slashed sun symbol, so the slash is drawn, with a gap cut either side of it.
            if state == .off {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: bounds.minX + 1.5, y: bounds.maxY - 1.5))
                slash.line(to: NSPoint(x: bounds.maxX - 1.5, y: bounds.minY + 1.5))
                slash.lineCapStyle = .round
                NSGraphicsContext.current?.compositingOperation = .clear
                slash.lineWidth = 4
                slash.stroke()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setStroke()
                slash.lineWidth = 1.5
                slash.stroke()
            }
            if withDot {
                let dot: CGFloat = 6
                // Clear a ring around the dot so it stands apart from the rays.
                NSGraphicsContext.current?.compositingOperation = .clear
                NSBezierPath(
                    ovalIn: NSRect(x: bounds.maxX - dot - 2, y: bounds.maxY - dot - 2, width: dot + 2, height: dot + 2)
                )
                .fill()
                NSGraphicsContext.current?.compositingOperation = .sourceOver
                NSColor.black.setFill()
                NSBezierPath(
                    ovalIn: NSRect(x: bounds.maxX - dot - 1, y: bounds.maxY - dot - 1, width: dot, height: dot)
                )
                .fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = description(of: state, withDot: withDot)
        return image
    }

    private static func description(of state: DimmingState, withDot: Bool) -> String {
        let base =
            switch state {
            case .off: "Cathemeral: off"
            case .nothingDimmed: "Cathemeral: nothing dimmed"
            case .dimmed: "Cathemeral: a display is dimmed"
            }
        return withDot ? "\(base), a display is paused" : base
    }
}
