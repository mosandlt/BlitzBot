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
    @Published var prompts: [Mode: String]
    @Published var hasAPIKey: Bool
    @Published var vocabulary: [String]
    @Published var outputLanguage: OutputLanguage

    private let defaults = UserDefaults.standard

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        self.whisperBinary = defaults.string(forKey: "whisperBinary")
            ?? "/opt/homebrew/bin/whisper-cli"
        self.whisperModel = defaults.string(forKey: "whisperModel")
            ?? "\(home)/.blitzbot/models/ggml-large-v3-turbo.bin"
        self.model = defaults.string(forKey: "claudeModel") ?? "claude-sonnet-4-5"

        var prompts: [Mode: String] = [:]
        for mode in Mode.allCases {
            let key = "prompt.\(mode.rawValue)"
            prompts[mode] = defaults.string(forKey: key) ?? mode.defaultSystemPrompt
        }
        self.prompts = prompts
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

    func prompt(for mode: Mode) -> String {
        prompts[mode] ?? mode.defaultSystemPrompt
    }

    /// Returns the system prompt for a mode + resolved language ("de" or "en").
    /// If the user customized a prompt in Settings we use it as-is (no translation),
    /// otherwise we pick the language-appropriate default.
    func prompt(for mode: Mode, language: String) -> String {
        if let custom = prompts[mode], !custom.isEmpty { return custom }
        return mode.defaultSystemPrompt(for: language)
    }

    func save() {
        defaults.set(whisperBinary, forKey: "whisperBinary")
        defaults.set(whisperModel, forKey: "whisperModel")
        defaults.set(model, forKey: "claudeModel")
        defaults.set(vocabulary, forKey: "vocabulary")
        defaults.set(outputLanguage.rawValue, forKey: "outputLanguage")
        for (mode, prompt) in prompts {
            defaults.set(prompt, forKey: "prompt.\(mode.rawValue)")
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
