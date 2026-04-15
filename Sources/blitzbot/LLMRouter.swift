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
                        config: AppConfig) async throws -> String {
        if let profile = config.profileStore.activeProfile {
            return try await rewriteWith(profile: profile, config: config,
                                         text: text, systemPrompt: systemPrompt)
        }
        return try await rewriteLegacy(config: config, text: text, systemPrompt: systemPrompt)
    }

    // MARK: - Profile path

    @MainActor
    private static func rewriteWith(profile: ConnectionProfile,
                                    config: AppConfig,
                                    text: String,
                                    systemPrompt: String) async throws -> String {
        let secret = config.profileStore.secret(for: profile)
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
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)

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
        }
    }

    // MARK: - Legacy path

    @MainActor
    private static func rewriteLegacy(config: AppConfig,
                                      text: String,
                                      systemPrompt: String) async throws -> String {
        switch config.llmProvider {
        case .anthropic:
            guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
                throw error("Kein Anthropic API Key")
            }
            let client = AnthropicClient(apiKey: apiKey, model: config.model)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)

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
        }
    }

    // MARK: - Helpers

    private static func defaultModel(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic: return "claude-sonnet-4-5"
        case .openai:    return "gpt-4o-mini"
        case .ollama:    return "llama3.2:latest"
        }
    }

    private static func error(_ message: String) -> NSError {
        NSError(domain: "LLMRouter", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
