import AppKit
import ApplicationServices
import Carbon
import Foundation

struct SelectedTextCapture {
    let text: String
    let replacementTarget: TextReplacementTarget
    let source: String
}

enum SelectedTextFetchResult {
    case success(SelectedTextCapture)
    case failure(String)
}

@MainActor
struct TextReplacementTarget {
    let application: NSRunningApplication?
    let applicationElement: AXUIElement?
    let focusedElement: AXUIElement?
    let selectedRange: NSRange?
}

@MainActor
struct SelectedTextFetcher {
    static func isAccessibilityGranted(promptIfNeeded: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": promptIfNeeded] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    func fetchSelectedText(preferredApplication: NSRunningApplication? = nil) async -> SelectedTextFetchResult {
        let target = currentTarget(preferredApplication: preferredApplication)

        if !Self.isAccessibilityGranted(promptIfNeeded: false) {
            if let text = await clipboardFallbackSelectedText(target: target) {
                return .success(SelectedTextCapture(text: text, replacementTarget: target, source: "Clipboard fallback"))
            }
            return .failure("Accessibility is disabled, and clipboard fallback did not capture selected text.")
        }

        for _ in 0..<3 {
            if let capture = accessibilitySelectedText(target: target) {
                return .success(capture)
            }
            try? await Task.sleep(for: .milliseconds(90))
        }

        if let text = await clipboardFallbackSelectedText(target: target) {
            return .success(SelectedTextCapture(text: text, replacementTarget: target, source: "Clipboard fallback"))
        }

        let appName = target.application?.localizedName ?? "the current app"
        return .failure("Could not read selected text from \(appName). Accessibility text lookup and clipboard fallback both failed.")
    }

    private func accessibilitySelectedText(target: TextReplacementTarget) -> SelectedTextCapture? {
        guard let element = target.focusedElement else {
            return nil
        }

        let currentRange = selectedRange(on: element)
        let replacementTarget = TextReplacementTarget(
            application: target.application,
            applicationElement: target.applicationElement,
            focusedElement: element,
            selectedRange: currentRange
        )

        if let directSelection = stringAttribute(kAXSelectedTextAttribute as CFString, on: element) {
            return SelectedTextCapture(text: directSelection, replacementTarget: replacementTarget, source: "Accessibility selected text")
        }

        guard
            let fullValue = stringAttribute(kAXValueAttribute as CFString, on: element),
            let selectedRange = currentRange
        else {
            return nil
        }

        guard let range = Range(selectedRange, in: fullValue) else {
            return nil
        }

        return SelectedTextCapture(
            text: String(fullValue[range]),
            replacementTarget: replacementTarget,
            source: "Accessibility selected range"
        )
    }

    private func currentTarget(preferredApplication: NSRunningApplication?) -> TextReplacementTarget {
        let frontmostApplication = NSWorkspace.shared.frontmostApplication
        let preferredExternalApp = sanitizedExternalApplication(preferredApplication)
        let frontmostExternalApp = sanitizedExternalApplication(frontmostApplication)
        let fallbackApp = preferredExternalApp ?? frontmostExternalApp
        return TextReplacementTarget(
            application: fallbackApp,
            applicationElement: fallbackApp.map { AXUIElementCreateApplication($0.processIdentifier) },
            focusedElement: systemWideFocusedElement(),
            selectedRange: nil
        )
    }

    private func systemWideFocusedElement() -> AXUIElement? {
        guard Self.isAccessibilityGranted(promptIfNeeded: false) else {
            return nil
        }

        return copyFocusedElement(from: AXUIElementCreateSystemWide())
    }

    private func copyFocusedElement(from sourceElement: AXUIElement) -> AXUIElement? {
        var focusedElementRef: CFTypeRef?
        let focusedResult = AXUIElementCopyAttributeValue(
            sourceElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElementRef
        )

        guard focusedResult == .success, let focusedElement = focusedElementRef else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    private func stringAttribute(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let string = value as? String else {
            return nil
        }

        return string
    }

    private func selectedRange(on element: AXUIElement) -> NSRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &value
        )

        guard result == .success, let axValue = value, CFGetTypeID(axValue) == AXValueGetTypeID() else {
            return nil
        }

        let rangeValue = axValue as! AXValue
        guard AXValueGetType(rangeValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(rangeValue, .cfRange, &range) else {
            return nil
        }

        return NSRange(location: range.location, length: range.length)
    }

    private func clipboardFallbackSelectedText(target: TextReplacementTarget) async -> String? {
        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)

        for _ in 0..<4 {
            let sentinel = "__GRAMIVOX_COPY_SENTINEL__\(UUID().uuidString)"
            pasteboard.clearContents()
            pasteboard.setString(sentinel, forType: .string)
            let initialChangeCount = pasteboard.changeCount

            if let application = sanitizedExternalApplication(target.application) {
                application.activate()
            }
            try? await Task.sleep(for: .milliseconds(180))
            simulateCopyShortcut()
            try? await Task.sleep(for: .milliseconds(60))
            simulateCopyShortcut()

            let deadline = Date().addingTimeInterval(1.0)
            while Date() < deadline {
                try? await Task.sleep(for: .milliseconds(80))
                if pasteboard.changeCount != initialChangeCount {
                    let copiedText = pasteboard.string(forType: .string)
                    let trimmedText = copiedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                    if !trimmedText.isEmpty && copiedText != sentinel {
                        snapshot.restore(to: pasteboard)
                        return copiedText
                    }

                    break
                }
            }
        }

        snapshot.restore(to: pasteboard)
        return nil
    }

    private func sanitizedExternalApplication(_ application: NSRunningApplication?) -> NSRunningApplication? {
        guard let application else {
            return nil
        }

        return application.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : application
    }

    private func simulateCopyShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_C), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

@MainActor
final class TextReplacementController {
    func apply(_ replacementText: String, to target: TextReplacementTarget) async -> Bool {
        let trimmedText = replacementText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedText.isEmpty else {
            return false
        }

        if replaceViaAccessibility(trimmedText, target: target) {
            return true
        }

        return await replaceViaPaste(trimmedText, target: target)
    }

    private func replaceViaAccessibility(_ replacementText: String, target: TextReplacementTarget) -> Bool {
        guard let element = target.focusedElement else {
            return false
        }

        target.application?.activate()
        _ = setFocused(true, on: element)

        if let selectedRange = target.selectedRange {
            _ = setSelectedRange(selectedRange, on: element)
        }

        if setStringAttribute(kAXSelectedTextAttribute as CFString, value: replacementText, on: element) {
            if let selectedRange = target.selectedRange {
                let caretRange = NSRange(location: selectedRange.location + replacementText.utf16.count, length: 0)
                _ = setSelectedRange(caretRange, on: element)
            }
            return true
        }

        guard
            let selectedRange = target.selectedRange,
            let fullValue = stringAttribute(kAXValueAttribute as CFString, on: element),
            let range = Range(selectedRange, in: fullValue)
        else {
            return false
        }

        let updatedValue = fullValue.replacingCharacters(in: range, with: replacementText)
        guard setStringAttribute(kAXValueAttribute as CFString, value: updatedValue, on: element) else {
            return false
        }

        let caretRange = NSRange(location: selectedRange.location + replacementText.utf16.count, length: 0)
        _ = setSelectedRange(caretRange, on: element)
        return true
    }

    private func replaceViaPaste(_ replacementText: String, target: TextReplacementTarget) async -> Bool {
        guard let application = target.application else {
            return false
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot.capture(from: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(replacementText, forType: .string)

        application.activate()
        try? await Task.sleep(for: .milliseconds(180))

        if let element = target.focusedElement {
            _ = setFocused(true, on: element)
            if let selectedRange = target.selectedRange {
                _ = setSelectedRange(selectedRange, on: element)
            }
        }

        simulatePasteShortcut()
        try? await Task.sleep(for: .milliseconds(180))
        snapshot.restore(to: pasteboard)
        return true
    }

    private func simulatePasteShortcut() {
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            return
        }

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true)
        keyDown?.flags = .maskCommand

        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }

    private func stringAttribute(_ attribute: CFString, on element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute, &value)
        guard result == .success, let string = value as? String else {
            return nil
        }

        return string
    }

    private func setStringAttribute(_ attribute: CFString, value: String, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, attribute, value as CFTypeRef) == .success
    }

    private func setFocused(_ focused: Bool, on element: AXUIElement) -> Bool {
        AXUIElementSetAttributeValue(element, kAXFocusedAttribute as CFString, focused as CFTypeRef) == .success
    }

    private func setSelectedRange(_ selectedRange: NSRange, on element: AXUIElement) -> Bool {
        var range = CFRange(location: selectedRange.location, length: selectedRange.length)
        guard let value = AXValueCreate(.cfRange, &range) else {
            return false
        }

        return AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            value
        ) == .success
    }
}

private struct PasteboardSnapshot {
    let itemData: [[NSPasteboard.PasteboardType: Data]]

    static func capture(from pasteboard: NSPasteboard) -> PasteboardSnapshot {
        let items = pasteboard.pasteboardItems?.map { item in
            Dictionary(uniqueKeysWithValues: item.types.compactMap { type in
                item.data(forType: type).map { (type, $0) }
            })
        } ?? []

        return PasteboardSnapshot(itemData: items)
    }

    func restore(to pasteboard: NSPasteboard) {
        pasteboard.clearContents()

        let items = itemData.map { savedTypes in
            let item = NSPasteboardItem()
            for (type, data) in savedTypes {
                item.setData(data, forType: type)
            }
            return item
        }

        guard !items.isEmpty else {
            return
        }

        pasteboard.writeObjects(items)
    }
}
