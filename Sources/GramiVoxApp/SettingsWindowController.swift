import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSWindowController {
    init(coordinator: AppCoordinator, settings: AppSettings) {
        let rootView = SettingsView(coordinator: coordinator, settings: settings)
        let hostingView = NSHostingView(rootView: rootView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 340),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )

        window.title = "GramiVox Settings"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentView = hostingView

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}
