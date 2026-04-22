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

/// Transient hand-off from the global Office hotkey to the Office window. The
/// hotkey must grab the current selection + remember the source app *before*
/// blitzbot steals focus, so the window can pre-fill text and know where to
/// paste the result back. Cleared by `OfficeView.onAppear`.
struct PendingOfficeContent: Equatable {
    let text: String
    let sourceAppBundleID: String?
    let createdAt: Date
}

enum LLMProvider: String, CaseIterable, Identifiable, Codable {
    case anthropic, openai, ollama

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .anthropic: return "Anthropic Claude"
        case .openai:    return "OpenAI ChatGPT"
        case .ollama:    return "Ollama (lokal)"
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

    // Multi-provider LLM settings
    @Published var llmProvider: LLMProvider { didSet { defaults.set(llmProvider.rawValue, forKey: "llmProvider") } }
    @Published var openaiModel: String { didSet { defaults.set(openaiModel, forKey: "openaiModel") } }
    @Published var ollamaBaseURL: String { didSet { defaults.set(ollamaBaseURL, forKey: "ollamaBaseURL") } }
    @Published var ollamaModel: String { didSet { defaults.set(ollamaModel, forKey: "ollamaModel") } }
    @Published var hasOpenAIKey: Bool
    @Published var hasOllamaKey: Bool

    /// Connection profiles. When an active profile is set, it takes precedence over
    /// `llmProvider` / per-provider keys; otherwise the legacy path is used.
    let profileStore: ProfileStore

    /// Populated by the Office hotkey right before the window opens; consumed by
    /// `OfficeView.onAppear`. Never persisted.
    @Published var pendingOfficeContent: PendingOfficeContent?

    /// When `true`, `LLMRouter.rewrite(...)` pipes outgoing user text through
    /// `privacyEngine.anonymize(_:)` and the response back through
    /// `privacyEngine.deanonymize(_:)`. Off by default — existing behavior unchanged
    /// until the user explicitly opts in.
    @Published var privacyMode: Bool {
        didSet {
            defaults.set(privacyMode, forKey: "privacyMode")
            // Defense-in-depth: when the user turns privacy off, wipe the session
            // mapping so we're not sitting on a PII table.
            if !privacyMode { privacyEngine.reset() }
            Log.write("Privacy: mode \(privacyMode ? "ON" : "OFF")")
        }
    }

    /// In-memory PII mapping. Never written to disk. Cleared on toggle-off and
    /// on app quit (the engine is an ObservableObject owned by this AppConfig).
    let privacyEngine = PrivacyEngine()

    /// User-maintained list of terms that should ALWAYS be anonymized, even if
    /// NLTagger / NSDataDetector misses them. Typical use: short company
    /// abbreviations, internal project code names, user's own last
    /// name, etc. Persisted as a comma-separated string in UserDefaults.
    @Published var privacyCustomTerms: [String] {
        didSet {
            defaults.set(privacyCustomTerms, forKey: "privacyCustomTerms")
            privacyEngine.customTerms = privacyCustomTerms
        }
    }

    // Context-menu (macOS Services) settings
    @Published var serviceDefaultMode: Mode {
        didSet { defaults.set(serviceDefaultMode.rawValue, forKey: "serviceDefaultMode") }
    }
    @Published var serviceClipboardFallback: Bool {
        didSet { defaults.set(serviceClipboardFallback, forKey: "serviceClipboardFallback") }
    }

    /// When true, mode hotkeys behave as push-to-talk: hold to record, release to
    /// stop. When false (default), they toggle (press once to start, press again
    /// to stop) — the original v1.0 behavior.
    @Published var holdToTalk: Bool {
        didSet { defaults.set(holdToTalk, forKey: "holdToTalk") }
    }

    /// Show Apple `SpeechTranscriber` partial text in the HUD while recording.
    /// macOS 26+ + 16-core ANE only — silently no-op on older OS / 8-core-ANE
    /// hardware. The final paste-text always comes from whisper-cli; this is
    /// purely visual feedback during the recording phase.
    @Published var liveTranscriptionEnabled: Bool {
        didSet { defaults.set(liveTranscriptionEnabled, forKey: "liveTranscriptionEnabled") }
    }

    /// Preferred microphone (Core Audio device UID). nil = follow system default.
    /// Resolved to a live AudioDeviceID at recording start; if the device is gone,
    /// AudioRecorder falls back to system default silently.
    @Published var preferredMicUID: String? {
        didSet {
            if let uid = preferredMicUID {
                defaults.set(uid, forKey: "preferredMicUID")
            } else {
                defaults.removeObject(forKey: "preferredMicUID")
            }
        }
    }

    private let defaults = UserDefaults.standard
    private static let promptMigrationKey = "promptMigration.v1_0_4.customOnly"

    init() {
        // Register soft defaults. These apply when the user has never explicitly
        // set a value — any write via the normal `@Published` didSet chain wins
        // over what's registered here, so explicit opt-outs are preserved.
        //
        // Privacy Mode: defaults to ON. Outbound text is anonymized before it
        // leaves the machine; users who want the pre-v1.2.2 behavior can flip
        // it off in Settings → Allgemein → Privacy (their choice is persisted).
        UserDefaults.standard.register(defaults: [
            "privacyMode": true,
            "liveTranscriptionEnabled": true   // gated at runtime by ANE + macOS 26
        ])

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

        // LLM provider + per-provider settings
        if let raw = defaults.string(forKey: "llmProvider"),
           let provider = LLMProvider(rawValue: raw) {
            self.llmProvider = provider
        } else {
            self.llmProvider = .anthropic
        }
        self.openaiModel = defaults.string(forKey: "openaiModel") ?? "gpt-4o-mini"
        self.ollamaBaseURL = defaults.string(forKey: "ollamaBaseURL") ?? "http://localhost:11434"
        self.ollamaModel = defaults.string(forKey: "ollamaModel") ?? "llama3.2:latest"
        self.hasOpenAIKey = KeychainStore.loadOpenAIKey()?.isEmpty == false
        self.hasOllamaKey = KeychainStore.loadOllamaKey()?.isEmpty == false
        self.profileStore = ProfileStore()

        // Context-menu (macOS Services)
        if let raw = defaults.string(forKey: "serviceDefaultMode"),
           let mode = Mode(rawValue: raw), mode != .normal {
            self.serviceDefaultMode = mode
        } else {
            self.serviceDefaultMode = .business
        }

        // Privacy mode — default registered as `true` at the top of init (v1.2.2+).
        // Existing installs that had it explicitly turned off keep their setting.
        self.privacyMode = defaults.bool(forKey: "privacyMode")
        self.holdToTalk = defaults.bool(forKey: "holdToTalk")
        self.liveTranscriptionEnabled = defaults.bool(forKey: "liveTranscriptionEnabled")
        self.preferredMicUID = defaults.string(forKey: "preferredMicUID")
        // Custom anonymization terms (persistent, separate from the session mapping).
        // Read once into a local to avoid "self used before all stored properties
        // initialized" — then push into the engine at the very end of init.
        let storedTerms = defaults.stringArray(forKey: "privacyCustomTerms") ?? []
        self.privacyCustomTerms = storedTerms
        self.privacyEngine.customTerms = storedTerms
        let storedFallback = defaults.object(forKey: "serviceClipboardFallback")
        self.serviceClipboardFallback = storedFallback != nil
            ? defaults.bool(forKey: "serviceClipboardFallback")
            : true
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

    // MARK: - Per-provider key management

    func setOpenAIKey(_ key: String) throws {
        try KeychainStore.saveOpenAIKey(key)
        hasOpenAIKey = !key.isEmpty
    }

    func removeOpenAIKey() {
        KeychainStore.deleteOpenAIKey()
        hasOpenAIKey = false
    }

    func setOllamaKey(_ key: String) throws {
        try KeychainStore.saveOllamaKey(key)
        hasOllamaKey = !key.isEmpty
    }

    func removeOllamaKey() {
        KeychainStore.deleteOllamaKey()
        hasOllamaKey = false
    }
}
