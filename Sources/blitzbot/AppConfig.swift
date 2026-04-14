import Foundation

enum OutputLanguage: String, CaseIterable, Identifiable, Codable {
    case auto, de, en

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .auto: return "Auto"
        case .de:   return "Deutsch"
        case .en:   return "English"
        }
    }

    var whisperLanguageFlag: String {
        switch self {
        case .auto: return "auto"
        case .de:   return "de"
        case .en:   return "en"
        }
    }

    var badge: String {
        switch self {
        case .auto: return "AUTO"
        case .de:   return "DE"
        case .en:   return "EN"
        }
    }
}

final class AppConfig: ObservableObject {
    @Published var whisperBinary: String
    @Published var whisperModel: String
    @Published var model: String
    /// Explicit user overrides only. A missing key means "use the language-appropriate default".
    @Published var customPrompts: [Mode: String]
    /// When `true` for a mode, the custom prompt is appended to the language-appropriate
    /// default (separated by a blank line). When `false` or missing, the custom prompt
    /// replaces the default entirely (legacy behavior).
    @Published var customPromptAppendModes: [Mode: Bool]
    @Published var hasAPIKey: Bool
    @Published var vocabulary: [String]
    @Published var outputLanguage: OutputLanguage
    @Published var autoStopEnabled: Bool
    @Published var autoStopTimeout: TimeInterval

    private let defaults = UserDefaults.standard
    private static let promptMigrationKey = "promptMigration.v1_0_4.customOnly"

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.whisperBinary = defaults.string(forKey: "whisperBinary")
            ?? "/opt/homebrew/bin/whisper-cli"
        self.whisperModel = defaults.string(forKey: "whisperModel")
            ?? "\(home)/.blitzbot/models/ggml-large-v3-turbo.bin"
        self.model = defaults.string(forKey: "claudeModel") ?? "claude-sonnet-4-5"

        // One-time migration: older versions eagerly persisted the German default into
        // UserDefaults as if it were a user customization. Strip those so language-aware
        // routing actually works. Values that differ from the German default stay (real
        // user customizations).
        if !defaults.bool(forKey: Self.promptMigrationKey) {
            for mode in Mode.allCases {
                let key = "prompt.\(mode.rawValue)"
                guard let stored = defaults.string(forKey: key) else { continue }
                if stored == mode.defaultSystemPromptGermanForMigration {
                    defaults.removeObject(forKey: key)
                }
            }
            defaults.set(true, forKey: Self.promptMigrationKey)
        }

        var customPrompts: [Mode: String] = [:]
        var customPromptAppendModes: [Mode: Bool] = [:]
        for mode in Mode.allCases {
            let key = "prompt.\(mode.rawValue)"
            if let stored = defaults.string(forKey: key), !stored.isEmpty {
                customPrompts[mode] = stored
            }
            let appendKey = "prompt.\(mode.rawValue).appendToDefault"
            if defaults.object(forKey: appendKey) != nil {
                customPromptAppendModes[mode] = defaults.bool(forKey: appendKey)
            }
        }
        self.customPrompts = customPrompts
        self.customPromptAppendModes = customPromptAppendModes
        self.hasAPIKey = KeychainStore.loadAPIKey()?.isEmpty == false
        self.vocabulary = defaults.stringArray(forKey: "vocabulary") ?? []
        if let raw = defaults.string(forKey: "outputLanguage"),
           let lang = OutputLanguage(rawValue: raw) {
            self.outputLanguage = lang
        } else {
            self.outputLanguage = .auto
        }
        // Auto-stop defaults: enabled, 60 seconds
        let storedAutoStop = defaults.object(forKey: "autoStopEnabled")
        self.autoStopEnabled = storedAutoStop != nil ? defaults.bool(forKey: "autoStopEnabled") : true
        let storedTimeout = defaults.double(forKey: "autoStopTimeout")
        self.autoStopTimeout = storedTimeout > 0 ? storedTimeout : 60
    }

    var vocabularyPrompt: String {
        let cleaned = vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.joined(separator: ", ")
    }

    /// Legacy accessor. Returns German default unless the user set a custom override.
    /// Prefer `prompt(for:language:)`.
    func prompt(for mode: Mode) -> String {
        prompt(for: mode, language: "de")
    }

    /// Returns the system prompt for a mode + resolved language ("de" or "en").
    /// Priority:
    ///   1. No custom text → language-appropriate default
    ///   2. Custom text + append mode on → default + blank line + custom
    ///   3. Custom text + append mode off → custom replaces default
    func prompt(for mode: Mode, language: String) -> String {
        let fallback = mode.defaultSystemPrompt(for: language)
        guard let custom = customPrompts[mode], !custom.isEmpty else { return fallback }
        if customPromptAppendModes[mode] == true {
            let base = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
            let addon = custom.trimmingCharacters(in: .whitespacesAndNewlines)
            if base.isEmpty { return addon }
            return base + "\n\n" + addon
        }
        return custom
    }

    /// Returns the resolved prompt for display in Settings when the user has no override.
    /// Shows the default in the configured output language, or German for auto-mode.
    func displayDefaultPrompt(for mode: Mode) -> String {
        let lang: String
        switch outputLanguage {
        case .de, .auto: lang = "de"
        case .en:        lang = "en"
        }
        return mode.defaultSystemPrompt(for: lang)
    }

    func save() {
        defaults.set(whisperBinary, forKey: "whisperBinary")
        defaults.set(whisperModel, forKey: "whisperModel")
        defaults.set(model, forKey: "claudeModel")
        defaults.set(vocabulary, forKey: "vocabulary")
        defaults.set(outputLanguage.rawValue, forKey: "outputLanguage")
        defaults.set(autoStopEnabled, forKey: "autoStopEnabled")
        defaults.set(autoStopTimeout, forKey: "autoStopTimeout")
        for mode in Mode.allCases {
            let key = "prompt.\(mode.rawValue)"
            if let value = customPrompts[mode], !value.isEmpty {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
            let appendKey = "prompt.\(mode.rawValue).appendToDefault"
            if let flag = customPromptAppendModes[mode] {
                defaults.set(flag, forKey: appendKey)
            } else {
                defaults.removeObject(forKey: appendKey)
            }
        }
    }

    func setAPIKey(_ key: String) throws {
        try KeychainStore.saveAPIKey(key)
        hasAPIKey = !key.isEmpty
    }

    func removeAPIKey() {
        KeychainStore.deleteAPIKey()
        hasAPIKey = false
    }
}
