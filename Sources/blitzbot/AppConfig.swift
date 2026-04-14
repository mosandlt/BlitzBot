import Foundation

final class AppConfig: ObservableObject {
    @Published var whisperBinary: String
    @Published var whisperModel: String
    @Published var model: String
    @Published var prompts: [Mode: String]
    @Published var hasAPIKey: Bool
    @Published var vocabulary: [String]

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
    }

    var vocabularyPrompt: String {
        let cleaned = vocabulary.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return cleaned.joined(separator: ", ")
    }

    func prompt(for mode: Mode) -> String {
        prompts[mode] ?? mode.defaultSystemPrompt
    }

    func save() {
        defaults.set(whisperBinary, forKey: "whisperBinary")
        defaults.set(whisperModel, forKey: "whisperModel")
        defaults.set(model, forKey: "claudeModel")
        defaults.set(vocabulary, forKey: "vocabulary")
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
