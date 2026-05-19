import AppKit
import Combine

@MainActor
final class StatusBarController: NSObject, NSMenuDelegate {
    private let coordinator: AppCoordinator
    private let settings: AppSettings
    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    private let statusMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let hotkeyMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
    private let openLastPopupMenuItem = NSMenuItem(title: "Open Last Popup", action: #selector(openLastPopup), keyEquivalent: "")

    init(coordinator: AppCoordinator, settings: AppSettings) {
        self.coordinator = coordinator
        self.settings = settings
        super.init()
    }

    func install() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            let image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "GramiVox")
            image?.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
            button.toolTip = "GramiVox"
        }

        rebuildMenu()
        bindState()
    }

    private func bindState() {
        coordinator.$statusMessage
            .sink { [weak self] _ in
                self?.refreshMenuState()
            }
            .store(in: &cancellables)

        coordinator.$lastPrompt
            .sink { [weak self] _ in
                self?.refreshMenuState()
            }
            .store(in: &cancellables)

        settings.objectWillChange
            .sink { [weak self] in
                self?.refreshMenuState()
            }
            .store(in: &cancellables)
    }

    private func rebuildMenu() {
        menu.delegate = self
        menu.removeAllItems()

        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)

        let captureItem = NSMenuItem(title: "Capture Selected Text", action: #selector(captureSelection), keyEquivalent: "")
        captureItem.target = self
        menu.addItem(captureItem)

        openLastPopupMenuItem.target = self
        menu.addItem(openLastPopupMenuItem)

        let testPopupItem = NSMenuItem(title: "Show Test Popup", action: #selector(showTestPopup), keyEquivalent: "")
        testPopupItem.target = self
        menu.addItem(testPopupItem)

        menu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        let accessibilityItem = NSMenuItem(title: "Request Accessibility Access", action: #selector(requestAccessibility), keyEquivalent: "")
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        hotkeyMenuItem.isEnabled = false
        menu.addItem(hotkeyMenuItem)

        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit GramiVox", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
        refreshMenuState()
    }

    private func refreshMenuState() {
        statusMenuItem.title = coordinator.statusMessage
        hotkeyMenuItem.title = "Hotkey: \(settings.hotKeyConfiguration.displayString)"
        openLastPopupMenuItem.isEnabled = !coordinator.lastPrompt.isEmpty
    }

    func menuWillOpen(_ menu: NSMenu) {
        refreshMenuState()
    }

    @objc private func captureSelection() {
        Task {
            await coordinator.captureSelectionFromMenu()
        }
    }

    @objc private func openLastPopup() {
        coordinator.openPopupWithLastPrompt()
    }

    @objc private func showTestPopup() {
        coordinator.showTestPopup()
    }

    @objc private func openSettings() {
        coordinator.openSettings()
    }

    @objc private func requestAccessibility() {
        coordinator.requestAccessibilityAccess()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
