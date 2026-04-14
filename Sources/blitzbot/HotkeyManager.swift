import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let modeNormal   = Self("modeNormal",   default: .init(.one,   modifiers: [.command, .option]))
    static let modeBusiness = Self("modeBusiness", default: .init(.two,   modifiers: [.command, .option]))
    static let modePlus     = Self("modePlus",     default: .init(.three, modifiers: [.command, .option]))
    static let modeRage     = Self("modeRage",     default: .init(.four,  modifiers: [.command, .option]))
    static let modeEmoji    = Self("modeEmoji",    default: .init(.five,  modifiers: [.command, .option]))
}

extension Mode {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .normal:   return .modeNormal
        case .business: return .modeBusiness
        case .plus:     return .modePlus
        case .rage:     return .modeRage
        case .emoji:    return .modeEmoji
        }
    }

    var defaultShortcutLabel: String {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description
            ?? fallbackShortcutLabel
    }

    private var fallbackShortcutLabel: String {
        switch self {
        case .normal:   return "⌘⌥1"
        case .business: return "⌘⌥2"
        case .plus:     return "⌘⌥3"
        case .rage:     return "⌘⌥4"
        case .emoji:    return "⌘⌥5"
        }
    }
}

final class HotkeyManager {
    var onTrigger: ((Mode) -> Void)?

    private static let migrationKey = "hotkeyMigration.v1_0_1.businessModeAdded"

    func register() {
        migrateIfNeeded()
        for mode in Mode.allCases {
            KeyboardShortcuts.onKeyDown(for: mode.shortcutName) { [weak self] in
                self?.onTrigger?(mode)
            }
        }
    }

    private func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.migrationKey) else { return }
        for mode in Mode.allCases {
            KeyboardShortcuts.reset(mode.shortcutName)
        }
        defaults.set(true, forKey: Self.migrationKey)
        Log.write("Hotkeys migrated: reset all mode shortcuts to v1.0.1 defaults")
    }
}
