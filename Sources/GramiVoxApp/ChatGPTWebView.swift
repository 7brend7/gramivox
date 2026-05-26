import AppKit
import SwiftUI
import WebKit

@MainActor
final class ChatGPTWebViewModel: ObservableObject {
    @Published var prompt = ""

    private weak var webView: WKWebView?
    private var hasLoadedInitialPage = false

    func attach(_ webView: WKWebView) {
        self.webView = webView
    }

    func loadIfNeeded() {
        guard let webView, !hasLoadedInitialPage else { return }
        hasLoadedInitialPage = true
        webView.load(URLRequest(url: URL(string: "https://chatgpt.com/")!))
    }

    func injectPromptIfPossible() {
        guard let webView, !prompt.isEmpty else { return }
        guard let promptJSON = prompt.jsonEncodedForJavaScript else { return }

        let script = "window.__gramivoxSetPrompt(\(promptJSON));"
        webView.evaluateJavaScript(script) { [weak self] _, _ in
            Task { @MainActor in
                await self?.clickComposerSubmitButtonUntilSuccessful()
            }
        }
    }

    func selectedReplyText(fallbackToLatestReply: Bool = false) async -> String? {
        guard let webView else {
            return nil
        }

        let script = fallbackToLatestReply
            ? "window.__gramivoxGetSelectedOrLatestAssistantText?.();"
            : "window.__gramivoxGetSelectionText?.();"

        guard let result = try? await webView.evaluateJavaScriptStringAsync(script) else {
            return nil
        }

        let trimmed = result.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func clickComposerSubmitButtonUntilSuccessful() async {
        for _ in 0..<20 {
            if await clickComposerSubmitButtonIfPossible() {
                return
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    private func clickComposerSubmitButtonIfPossible() async -> Bool {
        guard let webView, let window = webView.window, window.isVisible else {
            return false
        }

        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(webView)

        let script = """
        (() => {
          const button = document.querySelector("#composer-submit-button");
          if (!button || button.disabled) return "";
          const label = [
            button.getAttribute("aria-label") || "",
            button.getAttribute("data-testid") || "",
            button.textContent || ""
          ].join(" ").toLowerCase();
          if (label.includes("stop") || label.includes("cancel")) return "";
          const style = window.getComputedStyle(button);
          if (style.display === "none" || style.visibility === "hidden") return "";
          const rect = button.getBoundingClientRect();
          if (rect.width <= 0 || rect.height <= 0) return "";
          return `${rect.left + rect.width / 2},${rect.top + rect.height / 2}`;
        })();
        """

        guard
            let coordinateString = try? await webView.evaluateJavaScriptStringAsync(script),
            !coordinateString.isEmpty
        else {
            return false
        }

        let parts = coordinateString.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else {
            return false
        }

        let domPoint = NSPoint(x: parts[0], y: parts[1])
        let viewPoint = NSPoint(
            x: domPoint.x,
            y: webView.isFlipped ? domPoint.y : webView.bounds.height - domPoint.y
        )
        let windowPoint = webView.convert(viewPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)

        postMouseClick(at: screenPoint)
        return true
    }

    private func postMouseClick(at appKitScreenPoint: NSPoint) {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let maximumScreenY = NSScreen.screens.reduce(appKitScreenPoint.y) { maximumY, screen in
            max(maximumY, screen.frame.maxY)
        }
        let quartzPoint = CGPoint(
            x: appKitScreenPoint.x,
            y: maximumScreenY - appKitScreenPoint.y
        )

        let mouseDown = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseDown,
            mouseCursorPosition: quartzPoint,
            mouseButton: .left
        )
        let mouseUp = CGEvent(
            mouseEventSource: source,
            mouseType: .leftMouseUp,
            mouseCursorPosition: quartzPoint,
            mouseButton: .left
        )

        mouseDown?.post(tap: CGEventTapLocation.cghidEventTap)
        mouseUp?.post(tap: CGEventTapLocation.cghidEventTap)
    }
}

struct ChatGPTWebView: NSViewRepresentable {
    @ObservedObject var model: ChatGPTWebViewModel

    func makeCoordinator() -> Coordinator {
        Coordinator(model: model)
    }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.userContentController.addUserScript(
            WKUserScript(
                source: Self.promptInjectionScript,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isInspectable = true
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        model.attach(webView)
        model.loadIfNeeded()
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        model.attach(nsView)
        model.injectPromptIfPossible()
    }

    static let promptInjectionScript = """
    (() => {
      function normalizeText(value) {
        return (value || "").replace(/\\s+\\n/g, "\\n").trim();
      }

      function isVisible(element) {
        if (!element) return false;
        const style = window.getComputedStyle(element);
        if (style.display === "none" || style.visibility === "hidden") return false;
        const rect = element.getBoundingClientRect();
        return rect.width > 0 && rect.height > 0;
      }

      function removeComposerNotice() {
        document.querySelectorAll("#thread-bottom aside").forEach((element) => {
          element.remove();
        });
      }

      function installComposerNoticeObserver() {
        if (window.__gramivoxComposerNoticeObserver) {
          return;
        }

        window.__gramivoxComposerNoticeObserver = new MutationObserver(() => {
          removeComposerNotice();
        });

        const root = document.querySelector("#thread-bottom") || document.documentElement || document.body;
        if (root) {
          window.__gramivoxComposerNoticeObserver.observe(root, {
            childList: true,
            subtree: true
          });
        }

        let attempts = 0;
        const interval = setInterval(() => {
          attempts += 1;
          removeComposerNotice();
          if (attempts > 20) {
            clearInterval(interval);
          }
        }, 250);
      }

      function setElementValue(element, value) {
        if (!element) return false;
        element.focus();
        window.__gramivoxPromptElement = element;

        if (element.tagName === "TEXTAREA" || element instanceof HTMLTextAreaElement) {
          const descriptor = Object.getOwnPropertyDescriptor(HTMLTextAreaElement.prototype, "value");
          descriptor?.set?.call(element, value);
          element.setAttribute("value", value);
          element.dispatchEvent(new Event("input", { bubbles: true }));
          element.dispatchEvent(new Event("change", { bubbles: true }));
          element.dispatchEvent(new KeyboardEvent("keyup", {
            key: " ",
            code: "Space",
            bubbles: true
          }));
          return true;
        }

        if (element.isContentEditable) {
          element.textContent = value;
          element.dispatchEvent(new InputEvent("input", {
            bubbles: true,
            inputType: "insertText",
            data: value
          }));
          return true;
        }

        return false;
      }

      function promptContainer() {
        const element = window.__gramivoxPromptElement;
        if (!element) return null;

        return (
          element.closest("form") ||
          element.closest("[data-testid='composer-root']") ||
          element.closest("[role='form']") ||
          element.parentElement
        );
      }

      function tryApplyPrompt(value) {
        const selectors = [
          "#prompt-textarea",
          "[data-testid='composer-root'] textarea",
          "form textarea",
          "textarea[placeholder*='Ask']",
          "textarea[placeholder*='Message']",
          "[data-testid='composer-root'] [contenteditable='true']",
          "form [contenteditable='true']"
        ];

        for (const selector of selectors) {
          const element = document.querySelector(selector);
          if (setElementValue(element, value)) {
            return true;
          }
        }

        return false;
      }

      function getSelectionText() {
        return normalizeText(window.getSelection?.()?.toString?.() || "");
      }

      function focusPrompt() {
        const element = window.__gramivoxPromptElement;
        if (!element) return false;

        element.focus();
        if (typeof element.setSelectionRange === "function" && typeof element.value === "string") {
          const end = element.value.length;
          element.setSelectionRange(end, end);
        }
        return true;
      }

      function assistantCandidates() {
        const direct = Array.from(document.querySelectorAll("[data-message-author-role='assistant']"));
        if (direct.length) return direct;

        return Array.from(document.querySelectorAll("main article"));
      }

      function getLatestAssistantText() {
        const candidates = assistantCandidates().reverse();
        for (const candidate of candidates) {
          const text = normalizeText(candidate.innerText || candidate.textContent || "");
          if (!text) continue;
          if (text.includes("ChatGPT can make mistakes")) continue;
          if (text === "ChatGPT") continue;
          return text;
        }

        return "";
      }

      window.__gramivoxSetPrompt = (value) => {
        installComposerNoticeObserver();
        removeComposerNotice();
        window.__gramivoxPendingPrompt = value;
        if (tryApplyPrompt(value)) {
          return true;
        }

        if (!window.__gramivoxObserver) {
          window.__gramivoxObserver = new MutationObserver(() => {
            removeComposerNotice();
            if (window.__gramivoxPendingPrompt && tryApplyPrompt(window.__gramivoxPendingPrompt)) {
              window.__gramivoxPendingPrompt = null;
            }
          });

          const root = document.documentElement || document.body;
          if (root) {
            window.__gramivoxObserver.observe(root, {
              childList: true,
              subtree: true
            });
          }
        }

        return false;
      };

      installComposerNoticeObserver();
      removeComposerNotice();
      window.__gramivoxGetSelectionText = () => getSelectionText();
      window.__gramivoxGetSelectedOrLatestAssistantText = () => {
        const selected = getSelectionText();
        if (selected) {
          return selected;
        }

        return getLatestAssistantText();
      };
      window.__gramivoxFocusPrompt = () => focusPrompt();
    })();
    """

    final class Coordinator: NSObject, WKNavigationDelegate {
        private let model: ChatGPTWebViewModel

        init(model: ChatGPTWebViewModel) {
            self.model = model
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.attach(webView)
            model.injectPromptIfPossible()
        }
    }
}

private extension String {
    var jsonEncodedForJavaScript: String? {
        guard let data = try? JSONEncoder().encode(self) else {
            return nil
        }

        return String(data: data, encoding: .utf8)
    }
}

private extension WKWebView {
    @MainActor
    func evaluateJavaScriptStringAsync(_ script: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            evaluateJavaScript(script) { result, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: result as? String)
                }
            }
        }
    }
}
