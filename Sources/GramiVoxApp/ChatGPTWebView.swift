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
        webView.evaluateJavaScript(script)
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

      function dispatchTrustedLikeClick(button) {
        const events = ["pointerdown", "mousedown", "pointerup", "mouseup", "click"];
        for (const type of events) {
          const event = new MouseEvent(type, {
            bubbles: true,
            cancelable: true,
            view: window
          });
          button.dispatchEvent(event);
        }
      }

      function isLikelySendButton(button) {
        if (!button || button.disabled || !isVisible(button)) return false;

        const label = [
          button.getAttribute("aria-label") || "",
          button.getAttribute("data-testid") || "",
          button.textContent || ""
        ].join(" ").toLowerCase();

        if (label.includes("voice") || label.includes("attach") || label.includes("upload") || label.includes("plus")) {
          return false;
        }

        if (label.includes("send") || label.includes("submit") || label.includes("arrow")) {
          return true;
        }

        const rect = button.getBoundingClientRect();
        return rect.width <= 80 && rect.height <= 80;
      }

      function clickSendButton() {
        const container = promptContainer();
        const selectors = [
          "button[data-testid='send-button']",
          "button[data-testid*='send']",
          "button[aria-label='Send prompt']",
          "button[aria-label='Send message']",
          "button[aria-label*='Send']",
          "button[aria-label='Submit']",
          "form button[type='submit']"
        ];

        for (const selector of selectors) {
          const scope = container || document;
          const button = scope.querySelector(selector) || document.querySelector(selector);
          if (!button) continue;
          if (!isLikelySendButton(button)) continue;
          dispatchTrustedLikeClick(button);
          return true;
        }

        if (container) {
          const buttons = Array.from(container.querySelectorAll("button"))
            .filter((button) => isLikelySendButton(button));

          const rightmostButton = buttons.sort((a, b) => {
            const rectA = a.getBoundingClientRect();
            const rectB = b.getBoundingClientRect();
            return rectB.right - rectA.right;
          })[0];

          if (rightmostButton) {
            dispatchTrustedLikeClick(rightmostButton);
            return true;
          }
        }

        return false;
      }

      function submitPrompt() {
        let attempts = 0;
        const trySubmit = () => {
          attempts += 1;

          if (clickSendButton()) {
            return;
          }

          const container = promptContainer();
          if (container && typeof container.requestSubmit === "function") {
            try {
              container.requestSubmit();
              return;
            } catch {}
          }

          const active = document.activeElement;
          if (active) {
            active.focus();
            const enterDown = new KeyboardEvent("keydown", {
              key: "Enter",
              code: "Enter",
              keyCode: 13,
              which: 13,
              bubbles: true
            });
            const enterPress = new KeyboardEvent("keypress", {
              key: "Enter",
              code: "Enter",
              keyCode: 13,
              which: 13,
              bubbles: true
            });
            const enterUp = new KeyboardEvent("keyup", {
              key: "Enter",
              code: "Enter",
              keyCode: 13,
              which: 13,
              bubbles: true
            });
            active.dispatchEvent(enterDown);
            active.dispatchEvent(enterPress);
            active.dispatchEvent(enterUp);
          }

          if (attempts < 8) {
            setTimeout(trySubmit, 180);
            return;
          }
        };

        setTimeout(trySubmit, 180);
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
        window.__gramivoxPendingPrompt = value;
        if (tryApplyPrompt(value)) {
          submitPrompt();
          return true;
        }

        if (!window.__gramivoxObserver) {
          window.__gramivoxObserver = new MutationObserver(() => {
            if (window.__gramivoxPendingPrompt && tryApplyPrompt(window.__gramivoxPendingPrompt)) {
              window.__gramivoxPendingPrompt = null;
              submitPrompt();
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
