import AppKit
import Combine
import Foundation

@MainActor
final class AppCoordinator: ObservableObject {
    static let shared = AppCoordinator()

    @Published var accessibilityGranted = SelectedTextFetcher.isAccessibilityGranted(promptIfNeeded: false)
    @Published var statusMessage = "Press Control + Option + G to capture selected text into ChatGPT."
    @Published var lastSelectedText = ""
    @Published var lastPrompt = ""

    private let hotKeyCenter = HotKeyCenter()
    private let selectedTextFetcher = SelectedTextFetcher()
    private let textReplacementController = TextReplacementController()
    private let settings = AppSettings.shared
    private let workspaceNotificationCenter = NSWorkspace.shared.notificationCenter
    private var hasStarted = false
    private var isCaptureInProgress = false
    private var lastReplacementTarget: TextReplacementTarget?
    private var lastExternalApplication: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()
    private lazy var settingsWindowController = SettingsWindowController(coordinator: self, settings: settings)

    private lazy var popupController = CursorPopupController(
        onApplyCorrectedText: { [weak self] text in
            Task { @MainActor in
                await self?.applyCorrectedText(text)
            }
        }
    )

    private init() {}

    func start() {
        guard !hasStarted else { return }
        hasStarted = true

        hotKeyCenter.onHotKey = { [weak self] in
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(140))
                await self?.captureSelectionAndOpenPopup()
            }
        }

        hotKeyCenter.registerHotKey(configuration: settings.hotKeyConfiguration)
        Publishers.CombineLatest4(
            settings.$hotKeyString,
            settings.$usesControl,
            settings.$usesOption,
            settings.$usesCommand.combineLatest(settings.$usesShift)
        )
            .sink { [weak self] _ in
                guard let self else { return }
                self.hotKeyCenter.registerHotKey(configuration: self.settings.hotKeyConfiguration)
                self.statusMessage = "Press \(self.settings.hotKeyConfiguration.displayString) to capture selected text into ChatGPT."
            }
            .store(in: &cancellables)

        workspaceNotificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in
                guard
                    let self,
                    let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                    app.processIdentifier != ProcessInfo.processInfo.processIdentifier
                else {
                    return
                }

                self.lastExternalApplication = app
            }
            .store(in: &cancellables)

        refreshAccessibilityStatus()
        statusMessage = "Press \(settings.hotKeyConfiguration.displayString) to capture selected text into ChatGPT."
    }

    func refreshAccessibilityStatus() {
        accessibilityGranted = SelectedTextFetcher.isAccessibilityGranted(promptIfNeeded: false)
    }

    func requestAccessibilityAccess() {
        accessibilityGranted = SelectedTextFetcher.isAccessibilityGranted(promptIfNeeded: true)
        if accessibilityGranted {
            statusMessage = "Accessibility access is enabled."
        } else {
            statusMessage = "Grant Accessibility access, then try the hotkey again."
        }
    }

    func openPopupWithLastPrompt() {
        guard !lastPrompt.isEmpty else {
            statusMessage = "No prompt is loaded yet. Select text in another app and press \(settings.hotKeyConfiguration.displayString)."
            return
        }

        popupController.present(prompt: lastPrompt)
        statusMessage = "Reopened the ChatGPT popup with the latest prompt."
    }

    func showTestPopup() {
        let testPrompt = settings.prompt(for: "Test selection from GramiVox")
        lastPrompt = testPrompt
        popupController.present(prompt: testPrompt)
        statusMessage = "Opened a test popup."
    }

    func captureSelectionAndOpenPopup() async {
        await captureSelectionAndOpenPopup(preferredApplication: nil, activatePreferredAppFirst: false)
    }

    func captureSelectionFromMenu() async {
        let preferredApp = lastExternalApplication
        await captureSelectionAndOpenPopup(preferredApplication: preferredApp, activatePreferredAppFirst: true)
    }

    private func captureSelectionAndOpenPopup(
        preferredApplication: NSRunningApplication?,
        activatePreferredAppFirst: Bool
    ) async {
        guard !isCaptureInProgress else { return }
        isCaptureInProgress = true
        defer { isCaptureInProgress = false }

        if activatePreferredAppFirst, let preferredApplication {
            preferredApplication.activate()
            try? await Task.sleep(for: .milliseconds(220))
        }

        statusMessage = "Looking for selected text..."

        let fetchResult = await selectedTextFetcher.fetchSelectedText(preferredApplication: preferredApplication)
        let capture: SelectedTextCapture
        switch fetchResult {
        case .success(let result):
            capture = result
        case .failure(let reason):
            refreshAccessibilityStatus()
            statusMessage = reason
            return
        }

        let trimmedText = capture.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            statusMessage = "The current selection is empty."
            return
        }

        let prompt = settings.prompt(for: trimmedText)
        lastSelectedText = trimmedText
        lastPrompt = prompt
        lastReplacementTarget = capture.replacementTarget

        popupController.present(prompt: prompt)
        statusMessage = "Loaded selected text via \(capture.source)."
    }

    func openSettings() {
        settingsWindowController.show()
    }

    private func applyCorrectedText(_ correctedText: String) async {
        guard let lastReplacementTarget else {
            statusMessage = "There is no captured selection to replace yet."
            return
        }

        statusMessage = "Applying corrected text back to the source app..."
        popupController.dismiss()

        let applied = await textReplacementController.apply(correctedText, to: lastReplacementTarget)
        statusMessage = applied
            ? "Applied corrected text back into the original app."
            : "Could not apply the corrected text automatically."
    }
}
