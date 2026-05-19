import Carbon
import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var promptTemplate: String {
        didSet {
            UserDefaults.standard.set(promptTemplate, forKey: Keys.promptTemplate)
        }
    }

    @Published var hotKeyString: String {
        didSet {
            let sanitized = Self.sanitizedKey(from: hotKeyString)
            if hotKeyString != sanitized {
                hotKeyString = sanitized
                return
            }
            UserDefaults.standard.set(hotKeyString, forKey: Keys.hotKeyString)
        }
    }

    @Published var usesControl: Bool {
        didSet { UserDefaults.standard.set(usesControl, forKey: Keys.usesControl) }
    }

    @Published var usesOption: Bool {
        didSet { UserDefaults.standard.set(usesOption, forKey: Keys.usesOption) }
    }

    @Published var usesCommand: Bool {
        didSet { UserDefaults.standard.set(usesCommand, forKey: Keys.usesCommand) }
    }

    @Published var usesShift: Bool {
        didSet { UserDefaults.standard.set(usesShift, forKey: Keys.usesShift) }
    }

    private init() {
        let defaults = UserDefaults.standard
        promptTemplate = defaults.string(forKey: Keys.promptTemplate) ?? "fix grammar or rephrase: [SELECTED TEXT]"
        hotKeyString = Self.sanitizedKey(from: defaults.string(forKey: Keys.hotKeyString) ?? "G")
        usesControl = defaults.object(forKey: Keys.usesControl) as? Bool ?? true
        usesOption = defaults.object(forKey: Keys.usesOption) as? Bool ?? true
        usesCommand = defaults.object(forKey: Keys.usesCommand) as? Bool ?? false
        usesShift = defaults.object(forKey: Keys.usesShift) as? Bool ?? false
    }

    var hotKeyConfiguration: HotKeyConfiguration {
        HotKeyConfiguration(
            keyString: hotKeyString,
            usesControl: usesControl,
            usesOption: usesOption,
            usesCommand: usesCommand,
            usesShift: usesShift
        )
    }

    func prompt(for selectedText: String) -> String {
        if promptTemplate.contains("[SELECTED TEXT]") {
            return promptTemplate.replacingOccurrences(of: "[SELECTED TEXT]", with: selectedText)
        }

        return "\(promptTemplate) \(selectedText)"
    }

    private static func sanitizedKey(from string: String) -> String {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard let scalar = trimmed.unicodeScalars.first else {
            return "G"
        }

        let supportedCharacters = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 -[]=;,.`/\\"
        guard supportedCharacters.unicodeScalars.contains(scalar) else {
            return "G"
        }

        return String(scalar)
    }

    private enum Keys {
        static let promptTemplate = "promptTemplate"
        static let hotKeyString = "hotKeyString"
        static let usesControl = "usesControl"
        static let usesOption = "usesOption"
        static let usesCommand = "usesCommand"
        static let usesShift = "usesShift"
    }
}

struct HotKeyConfiguration: Equatable {
    let keyString: String
    let usesControl: Bool
    let usesOption: Bool
    let usesCommand: Bool
    let usesShift: Bool

    var carbonModifiers: UInt32 {
        var flags: UInt32 = 0
        if usesControl { flags |= UInt32(controlKey) }
        if usesOption { flags |= UInt32(optionKey) }
        if usesCommand { flags |= UInt32(cmdKey) }
        if usesShift { flags |= UInt32(shiftKey) }
        return flags
    }

    var keyCode: UInt32? {
        Self.keyCodeMap[keyString]
    }

    var displayString: String {
        let pieces = [
            usesControl ? "Control" : nil,
            usesOption ? "Option" : nil,
            usesCommand ? "Command" : nil,
            usesShift ? "Shift" : nil,
            keyString
        ].compactMap { $0 }

        return pieces.joined(separator: " + ")
    }

    private static let keyCodeMap: [String: UInt32] = [
        "A": UInt32(kVK_ANSI_A), "B": UInt32(kVK_ANSI_B), "C": UInt32(kVK_ANSI_C),
        "D": UInt32(kVK_ANSI_D), "E": UInt32(kVK_ANSI_E), "F": UInt32(kVK_ANSI_F),
        "G": UInt32(kVK_ANSI_G), "H": UInt32(kVK_ANSI_H), "I": UInt32(kVK_ANSI_I),
        "J": UInt32(kVK_ANSI_J), "K": UInt32(kVK_ANSI_K), "L": UInt32(kVK_ANSI_L),
        "M": UInt32(kVK_ANSI_M), "N": UInt32(kVK_ANSI_N), "O": UInt32(kVK_ANSI_O),
        "P": UInt32(kVK_ANSI_P), "Q": UInt32(kVK_ANSI_Q), "R": UInt32(kVK_ANSI_R),
        "S": UInt32(kVK_ANSI_S), "T": UInt32(kVK_ANSI_T), "U": UInt32(kVK_ANSI_U),
        "V": UInt32(kVK_ANSI_V), "W": UInt32(kVK_ANSI_W), "X": UInt32(kVK_ANSI_X),
        "Y": UInt32(kVK_ANSI_Y), "Z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "-": UInt32(kVK_ANSI_Minus), "=": UInt32(kVK_ANSI_Equal),
        "[": UInt32(kVK_ANSI_LeftBracket), "]": UInt32(kVK_ANSI_RightBracket),
        ";": UInt32(kVK_ANSI_Semicolon), "'": UInt32(kVK_ANSI_Quote),
        ",": UInt32(kVK_ANSI_Comma), ".": UInt32(kVK_ANSI_Period),
        "/": UInt32(kVK_ANSI_Slash), "\\": UInt32(kVK_ANSI_Backslash),
        "`": UInt32(kVK_ANSI_Grave), " ": UInt32(kVK_Space)
    ]
}
