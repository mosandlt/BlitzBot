import Foundation

/// Single call site for outbound LLM requests.
///
/// Resolution order:
///   1. Active connection profile (if any) — uses its baseURL, authScheme, model, secret.
///   2. Legacy provider/key settings — preserved so existing installs keep working.
enum LLMRouter {
    @MainActor
    static func rewrite(text: String,
                        systemPrompt: String,
                        config: AppConfig,
                        mode: Mode? = nil) async throws -> String {
        // Privacy wrap — when enabled AND the target provider leaves the Mac,
        // anonymize outgoing user text, append a hint to the system prompt so
        // the LLM doesn't treat placeholders as unfilled template slots, and
        // de-anonymize the response. Skipped for local providers (Ollama,
        // Apple Intelligence) where the data never leaves the machine anyway.
        let provider = resolveProvider(config: config, override: nil)
        let (preparedText, preparedPrompt, engine) = applyPrivacyIfEnabled(
            text: text, systemPrompt: systemPrompt, config: config, provider: provider
        )
        let raw: String
        if let profile = config.profileStore.activeProfile {
            raw = try await rewriteWith(profile: profile, config: config,
                                        text: preparedText, systemPrompt: preparedPrompt,
                                        mode: mode)
        } else {
            raw = try await rewriteLegacy(config: config,
                                          text: preparedText, systemPrompt: preparedPrompt,
                                          mode: mode)
        }
        return engine?.deanonymize(raw) ?? raw
    }

    /// Profile-override path — used by the inline recovery flow to retry a failed
    /// request against a *different* profile than the currently active one, without
    /// mutating `config.profileStore.activeProfileID`. Same privacy wrap as above.
    @MainActor
    static func rewrite(text: String,
                        systemPrompt: String,
                        config: AppConfig,
                        profileOverride: ConnectionProfile,
                        mode: Mode? = nil) async throws -> String {
        let provider = resolveProvider(config: config, override: profileOverride)
        let (preparedText, preparedPrompt, engine) = applyPrivacyIfEnabled(
            text: text, systemPrompt: systemPrompt, config: config, provider: provider
        )
        let raw = try await rewriteWith(profile: profileOverride, config: config,
                                        text: preparedText, systemPrompt: preparedPrompt,
                                        mode: mode)
        return engine?.deanonymize(raw) ?? raw
    }

    /// Effective provider for a given call — used to decide whether the Privacy
    /// wrap has any value (it's skipped for local providers).
    @MainActor
    private static func resolveProvider(config: AppConfig,
                                        override: ConnectionProfile?) -> LLMProvider {
        if let override { return override.provider }
        if let active = config.profileStore.activeProfile { return active.provider }
        return config.llmProvider
    }

    /// When Privacy Mode is on AND the target provider is cloud-bound:
    ///   1. Anonymize the user text via `PrivacyEngine`.
    ///   2. Append a short bilingual hint to the system prompt so the LLM knows
    ///      the `[NAME_1]`-style tokens are *real* entities (not unfilled
    ///      template slots) and must be kept verbatim in its response — that way
    ///      our reverse pass can map them back to the originals.
    ///
    /// When off, or when the provider runs locally (Ollama / Apple Intelligence),
    /// returns the input unchanged and a nil engine so callers skip the reverse
    /// wrap. Local providers see the raw text because it never leaves the machine
    /// — anonymizing on the way to a local model would hurt output quality for
    /// zero privacy benefit.
    @MainActor
    private static func applyPrivacyIfEnabled(
        text: String,
        systemPrompt: String,
        config: AppConfig,
        provider: LLMProvider
    ) -> (String, String, PrivacyEngine?) {
        guard config.privacyMode else { return (text, systemPrompt, nil) }
        if provider.isLocal {
            Log.write("Privacy: skipped (local provider: \(provider.rawValue))")
            return (text, systemPrompt, nil)
        }
        let engine = config.privacyEngine
        let anonText = engine.anonymize(text)
        let hint = privacyPromptHint
        // Keep the original prompt first, hint last — LLMs typically weight
        // later instructions slightly higher for recent context.
        let trimmed = systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        let augmented = trimmed.isEmpty ? hint : trimmed + "\n\n" + hint
        return (anonText, augmented, engine)
    }

    /// Bilingual instruction appended to the system prompt when Privacy Mode is on.
    ///
    /// Notably we do NOT enumerate placeholder examples — earlier versions listed
    /// shapes like `[NAME_1]` / `[UNTERNEHMEN_1]` and the LLM took that as a hint
    /// to re-anonymize plain-text names on its own (e.g. rewriting a plain-text
    /// company mention into `[UNTERNEHMEN_1]`), which then failed the reverse
    /// lookup because no such mapping existed. The current wording focuses on:
    /// (a) if bracket-tokens appear, keep them verbatim, and (b) do NOT invent
    /// new ones.
    private static let privacyPromptHint = """
    Privacy-Modus Hinweis:
    Der Eingabetext kann bereits anonymisierte Tokens enthalten — Form: Großbuchstaben in eckigen \
    Klammern mit Unterstrich-Index (z. B. ein Token der Gestalt [XXXX_1]). Falls solche Tokens \
    vorkommen, übernimm sie EXAKT und UNVERÄNDERT in deine Antwort. Sie sind KEINE unausgefüllten \
    Template-Slots, keine Fehler und müssen nicht ausgefüllt oder ersetzt werden.
    Alles andere im Text bleibt so wie es ist: führe KEINE eigene Anonymisierung durch. Wörter die \
    NICHT in dem genannten Bracket-Format vorliegen (echte Eigennamen, Firmennamen, URLs etc.) gibst \
    du exakt so aus wie sie geliefert wurden — ersetze sie nicht durch Platzhalter.

    Privacy-mode note:
    The input may contain already-anonymized tokens — shape: uppercase letters inside square brackets \
    with an underscore index (e.g. a token shaped like [XXXX_1]). If any such tokens appear, keep them \
    EXACTLY and UNCHANGED in your response. They are NOT unfilled template slots, not errors, and \
    must not be filled in or replaced.
    Everything else stays as given: do NOT apply your own anonymization. Any word NOT in that bracket \
    form (real names, company names, URLs, etc.) must be output verbatim — do not substitute it with \
    a placeholder.
    """

    // MARK: - Profile path

    @MainActor
    private static func rewriteWith(profile: ConnectionProfile,
                                    config: AppConfig,
                                    text: String,
                                    systemPrompt: String,
                                    mode: Mode?) async throws -> String {
        // Prefer the profile-specific secret; fall back to the legacy per-provider key
        // for Anthropic/OpenAI profiles when the migration hasn't copied the secret yet
        // (e.g. first launch after upgrade or a failed Keychain rewrite).
        var secret = config.profileStore.secret(for: profile)
        let needsSecretFallback = profile.provider != .ollama && profile.provider != .appleIntelligence
        if (secret == nil || secret!.isEmpty) && needsSecretFallback {
            switch profile.provider {
            case .anthropic:
                if let legacyKey = KeychainStore.loadAPIKey(), !legacyKey.isEmpty {
                    Log.write("LLMRouter: profile \"\(profile.name)\" secret missing — using legacy anthropic-api-key as fallback")
                    secret = legacyKey
                    // Re-persist under the profile account so next call finds it directly.
                    try? KeychainStore.saveKey(legacyKey, account: profile.keychainAccount)
                }
            case .openai:
                if let legacyKey = KeychainStore.loadOpenAIKey(), !legacyKey.isEmpty {
                    Log.write("LLMRouter: profile \"\(profile.name)\" secret missing — using legacy openai-api-key as fallback")
                    secret = legacyKey
                    try? KeychainStore.saveKey(legacyKey, account: profile.keychainAccount)
                }
            case .ollama, .appleIntelligence: break
            }
        }

        let model = profile.preferredModel ?? defaultModel(for: profile.provider)

        switch profile.provider {
        case .anthropic:
            guard let key = secret, !key.isEmpty else {
                throw error("Profil \"\(profile.name)\": kein Key gesetzt")
            }
            let client = AnthropicClient(apiKey: key,
                                         model: model,
                                         baseURL: profile.baseURL,
                                         authScheme: profile.authScheme,
                                         sendAnthropicVersion: profile.sendAnthropicVersion)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt, mode: mode)

        case .openai:
            guard let key = secret, !key.isEmpty else {
                throw error("Profil \"\(profile.name)\": kein Key gesetzt")
            }
            let client = OpenAIClient(apiKey: key,
                                      model: model,
                                      baseURL: profile.baseURL,
                                      authScheme: profile.authScheme)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)

        case .ollama:
            let bearer = (profile.authScheme == .bearer) ? secret : nil
            let client = OllamaClient(baseURL: profile.baseURL,
                                      model: model,
                                      apiKey: bearer)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)

        case .appleIntelligence:
            let client = AppleIntelligenceClient()
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)
        }
    }

    // MARK: - Legacy path

    @MainActor
    private static func rewriteLegacy(config: AppConfig,
                                      text: String,
                                      systemPrompt: String,
                                      mode: Mode?) async throws -> String {
        switch config.llmProvider {
        case .anthropic:
            guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
                throw error("Kein Anthropic API Key")
            }
            let client = AnthropicClient(apiKey: apiKey, model: config.model)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt, mode: mode)

        case .openai:
            guard let apiKey = KeychainStore.loadOpenAIKey(), !apiKey.isEmpty else {
                throw error("Kein OpenAI API Key")
            }
            let client = OpenAIClient(apiKey: apiKey, model: config.openaiModel)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)

        case .ollama:
            let client = OllamaClient(baseURL: config.ollamaBaseURL,
                                      model: config.ollamaModel,
                                      apiKey: KeychainStore.loadOllamaKey())
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)

        case .appleIntelligence:
            // Legacy path (no connection profiles yet). Apple Intelligence has no
            // per-provider legacy settings, so we just call the on-device client.
            let client = AppleIntelligenceClient()
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)
        }
    }

    // MARK: - Helpers

    private static func defaultModel(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic:         return "claude-sonnet-4-5"
        case .openai:            return "gpt-4o-mini"
        case .ollama:            return "llama3.2:latest"
        case .appleIntelligence: return AppleIntelligenceClient.modelID
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "LLMRouter", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
