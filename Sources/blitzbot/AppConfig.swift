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
    @Published var hasAPIKey: Bool
    @Published var vocabulary: [String]
    @Published var outputLanguage: OutputLanguage

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
        for mode in Mode.allCases {
            let key = "prompt.\(mode.rawValue)"
            if let stored = defaults.string(forKey: key), !stored.isEmpty {
                customPrompts[mode] = stored
            }
        }
        self.customPrompts = customPrompts
        self.hasAPIKey = KeychainStore.loadAPIKey()?.isEmpty == false
        self.vocabulary = defaults.stringArray(forKey: "vocabulary") ?? []
        if let raw = defaults.string(forKey: "outputLanguage"),
           let lang = OutputLanguage(rawValue: raw) {
            self.outputLanguage = lang
        } else {
            self.outputLanguage = .auto
        }
    }

    var vocabularyPrompt: String {
        let cleaned = vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.joined(separator: ", ")
    }

    /// Legacy accessor. Returns German default unless the user set a custom override.
    /// Prefer `prompt(for:language:)`.
    func prompt(for mode: Mode) -> String {
        customPrompts[mode] ?? mode.defaultSystemPrompt
    }

    /// Returns the system prompt for a mode + resolved language ("de" or "en").
    /// Priority: explicit user override > language-appropriate default.
    func prompt(for mode: Mode, language: String) -> String {
        if let custom = customPrompts[mode], !custom.isEmpty { return custom }
        return mode.defaultSystemPrompt(for: language)
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
        for mode in Mode.allCases {
            let key = "prompt.\(mode.rawValue)"
            if let value = customPrompts[mode], !value.isEmpty {
                defaults.set(value, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
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
