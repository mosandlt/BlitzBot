import AppKit
import KeyboardShortcuts

extension KeyboardShortcuts.Name {
    static let modeNormal       = Self("modeNormal",       default: .init(.one,   modifiers: [.command, .option]))
    static let modeBusiness     = Self("modeBusiness",     default: .init(.two,   modifiers: [.command, .option]))
    static let modePlus         = Self("modePlus",         default: .init(.three, modifiers: [.command, .option]))
    static let modeRage         = Self("modeRage",         default: .init(.four,  modifiers: [.command, .option]))
    static let modeEmoji        = Self("modeEmoji",        default: .init(.five,  modifiers: [.command, .option]))
    static let modeAICommand    = Self("modeAICommand",    default: .init(.six,   modifiers: [.command, .option]))
    static let rewriteSelection = Self("rewriteSelection", default: .init(.zero,  modifiers: [.command, .option]))
    /// Office mode — no default. Earlier v1.2.0 builds defaulted to ⌘⌥O, but that
    /// collides with other apps (Outlook, etc). Set your own combo in Settings → Hotkeys.
    static let toggleOffice     = Self("toggleOffice")
}

extension Mode {
    var shortcutName: KeyboardShortcuts.Name {
        switch self {
        case .normal:     return .modeNormal
        case .business:   return .modeBusiness
        case .plus:       return .modePlus
        case .rage:       return .modeRage
        case .emoji:      return .modeEmoji
        case .aiCommand:  return .modeAICommand
        case .officeMode: return .toggleOffice
        }
    }

    var defaultShortcutLabel: String {
        KeyboardShortcuts.getShortcut(for: shortcutName)?.description
            ?? fallbackShortcutLabel
    }

    private var fallbackShortcutLabel: String {
        switch self {
        case .normal:     return "⌘⌥1"
        case .business:   return "⌘⌥2"
        case .plus:       return "⌘⌥3"
        case .rage:       return "⌘⌥4"
        case .emoji:     return "⌘⌥5"
        case .aiCommand:  return "⌘⌥6"
        case .officeMode: return "—"
        }
    }
}

// MARK: -

/// Listens for the configured hotkeys via a CGEventTap (requires Accessibility).
/// Requires only Bedienungshilfen — no Input Monitoring needed.
/// Shortcuts are read from UserDefaults (via KeyboardShortcuts) on every key-down,
/// so changes in Settings take effect immediately without restart.
final class HotkeyManager {
    var onTrigger: ((Mode) -> Void)?
    var onRewriteSelection: (() -> Void)?
    var onToggleOffice: (() -> Void)?

    private static let migrationKey = "hotkeyMigration.v1_0_1.businessModeAdded"
    private static let officeDefaultResetKey = "hotkeyMigration.v1_2_1.officeDefaultRemoved"

    // Kept alive so the tap is not released.
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    // Static back-reference used by the C callback to reach the Swift instance.
    private static weak var current: HotkeyManager?

    func register() {
        migrateIfNeeded()
        installEventTap()
    }

    // MARK: – CGEventTap

    private func installEventTap() {
        HotkeyManager.current = self

        let eventMask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: eventMask,
            callback: { _, _, event, _ -> Unmanaged<CGEvent>? in
                HotkeyManager.current?.handleKeyDown(event)
                return nil  // listenOnly — return value is ignored by the system
            },
            userInfo: nil
        ) else {
            Log.write("CGEventTap creation failed — Bedienungshilfen permission missing?")
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        self.eventTap = tap
        self.runLoopSource = source
        Log.write("CGEventTap installed (Accessibility-based, no Input Monitoring needed)")
    }

    private func handleKeyDown(_ event: CGEvent) {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let relevantFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskShift, .maskControl]
        let eventMods = event.flags.intersection(relevantFlags)

        // Voice-mode hotkeys only. Non-voice modes (e.g. officeMode) have their own
        // dedicated callbacks below so the hotkey doesn't accidentally start a recording.
        for mode in Mode.voiceModes {
            guard let shortcut = KeyboardShortcuts.getShortcut(for: mode.shortcutName),
                  let key = shortcut.key,
                  Int64(key.rawValue) == keyCode,
                  cgFlags(from: shortcut.modifiers) == eventMods
            else { continue }

            DispatchQueue.main.async { [weak self] in
                self?.onTrigger?(mode)
            }
            return
        }

        if let shortcut = KeyboardShortcuts.getShortcut(for: .rewriteSelection),
           let key = shortcut.key,
           Int64(key.rawValue) == keyCode,
           cgFlags(from: shortcut.modifiers) == eventMods {
            DispatchQueue.main.async { [weak self] in
                self?.onRewriteSelection?()
            }
            return
        }

        if let shortcut = KeyboardShortcuts.getShortcut(for: .toggleOffice),
           let key = shortcut.key,
           Int64(key.rawValue) == keyCode,
           cgFlags(from: shortcut.modifiers) == eventMods {
            DispatchQueue.main.async { [weak self] in
                self?.onToggleOffice?()
            }
        }
    }

    private func cgFlags(from mods: NSEvent.ModifierFlags) -> CGEventFlags {
        var f: CGEventFlags = []
        if mods.contains(.command) { f.insert(.maskCommand) }
        if mods.contains(.option)  { f.insert(.maskAlternate) }
        if mods.contains(.shift)   { f.insert(.maskShift) }
        if mods.contains(.control) { f.insert(.maskControl) }
        return f
    }

    // MARK: – Migration

    private func migrateIfNeeded() {
        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: Self.migrationKey) {
            for mode in Mode.allCases { KeyboardShortcuts.reset(mode.shortcutName) }
            defaults.set(true, forKey: Self.migrationKey)
            Log.write("Hotkeys migrated: reset all mode shortcuts to v1.0.1 defaults")
        }
        // v1.2.1 follow-up: earlier builds shipped ⌘⌥O as the Office default, which
        // collides with other apps. Drop the shortcut so users who never customized
        // it start clean; anyone who explicitly set their own combo is left alone.
        if !defaults.bool(forKey: Self.officeDefaultResetKey) {
            if let current = KeyboardShortcuts.getShortcut(for: .toggleOffice),
               current.key == .o,
               current.modifiers == [.command, .option] {
                KeyboardShortcuts.reset(.toggleOffice)
                Log.write("Hotkeys migrated: removed stale ⌘⌥O default for toggleOffice")
            }
            defaults.set(true, forKey: Self.officeDefaultResetKey)
        }
    }
}
