import AppKit
import SwiftUI

@MainActor
final class CursorPopupController {
    private let onApplyCorrectedText: (String) -> Void
    private var activeSession: PopupSession?
    private var localKeyMonitor: Any?
    private var globalKeyMonitor: Any?

    init(onApplyCorrectedText: @escaping (String) -> Void) {
        self.onApplyCorrectedText = onApplyCorrectedText
        installEscapeMonitors()
    }

    func present(prompt: String) {
        let session = makeSession()

        if let previousSession = activeSession {
            previousSession.panel.close()
        }

        activeSession = session

        let panel = session.panel
        let webViewModel = session.webViewModel
        webViewModel.prompt = prompt
        position(panel: panel)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        panel.makeMain()
        panel.orderFrontRegardless()
        webViewModel.loadIfNeeded()
        webViewModel.injectPromptIfPossible()
    }

    func dismiss() {
        activeSession?.panel.orderOut(nil)
    }

    private func makeSession() -> PopupSession {
        let webViewModel = ChatGPTWebViewModel()
        let contentView = PopupContentView(
            webViewModel: webViewModel,
            onApplyCorrectedText: onApplyCorrectedText
        )
        let panel = EscapeClosablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 560),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .transient]
        panel.becomesKeyOnlyIfNeeded = false
        panel.contentView = NSHostingView(rootView: contentView)
        panel.isReleasedWhenClosed = false

        webViewModel.loadIfNeeded()
        return PopupSession(panel: panel, webViewModel: webViewModel)
    }

    private func installEscapeMonitors() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            self?.dismiss()
            return nil
        }

        globalKeyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return }
            Task { @MainActor in
                self?.dismiss()
            }
        }
    }

    private func position(panel: NSPanel) {
        let cursorLocation = NSEvent.mouseLocation
        guard let screen = NSScreen.screens.first(where: { NSMouseInRect(cursorLocation, $0.frame, false) }) ?? NSScreen.main else {
            return
        }

        let visibleFrame = screen.visibleFrame
        let panelSize = panel.frame.size

        var originX = cursorLocation.x + 18
        var originY = cursorLocation.y - panelSize.height - 42

        originX = min(max(originX, visibleFrame.minX + 12), visibleFrame.maxX - panelSize.width - 12)
        originY = min(max(originY, visibleFrame.minY + 56), visibleFrame.maxY - panelSize.height - 20)

        panel.setFrameOrigin(NSPoint(x: originX, y: originY))
    }
}

private struct PopupSession {
    let panel: NSPanel
    let webViewModel: ChatGPTWebViewModel
}

private final class EscapeClosablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        orderOut(sender)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            orderOut(nil)
            return
        }

        super.keyDown(with: event)
    }
}

private struct PopupContentView: View {
    @ObservedObject var webViewModel: ChatGPTWebViewModel
    let onApplyCorrectedText: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            ChatGPTWebView(model: webViewModel)

            Divider()

            HStack {
                Spacer()

                Button("Apply Selection") {
                    Task {
                        if let correctedText = await webViewModel.selectedReplyText() {
                            onApplyCorrectedText(correctedText)
                        }
                    }
                }
                .keyboardShortcut(.return, modifiers: [.command])
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial)
        }
        .frame(width: 460, height: 560)
        .background(.thinMaterial)
    }
}
