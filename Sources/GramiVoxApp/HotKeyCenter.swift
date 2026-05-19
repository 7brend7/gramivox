import Carbon
import Foundation

final class HotKeyCenter {
    var onHotKey: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = UInt32(1)
    private let hotKeySignature = HotKeyCenter.fourCharCode("GMVX")

    func registerHotKey(configuration: HotKeyConfiguration) {
        unregisterHotKey()
        guard let keyCode = configuration.keyCode else {
            return
        }

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let userData = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            hotKeyHandler,
            1,
            &eventType,
            userData,
            &eventHandlerRef
        )

        let identifier = EventHotKeyID(signature: hotKeySignature, id: hotKeyID)
        RegisterEventHotKey(
            keyCode,
            configuration.carbonModifiers,
            identifier,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregisterHotKey() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }

        if let eventHandlerRef {
            RemoveEventHandler(eventHandlerRef)
            self.eventHandlerRef = nil
        }
    }

    deinit {
        unregisterHotKey()
    }
    private static func fourCharCode(_ string: String) -> OSType {
        string.utf16.reduce(0) { partialResult, value in
            (partialResult << 8) + OSType(value)
        }
    }
}

private let hotKeyHandler: EventHandlerUPP = { _, event, userData in
    guard let event, let userData else {
        return noErr
    }

    var hotKeyID = EventHotKeyID()
    GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )

    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
    if hotKeyID.id == 1 {
        center.onHotKey?()
    }

    return noErr
}
