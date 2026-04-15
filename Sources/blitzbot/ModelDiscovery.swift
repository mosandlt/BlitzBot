import Foundation

/// Fetches the list of available models from a provider endpoint.
///
/// Per-session only — results are not persisted.
enum ModelDiscovery {
    /// Lists models for the given profile. Secret is applied per the profile's auth scheme.
    /// Ollama ignores the secret unless `authScheme == .bearer`.
    static func list(profile: ConnectionProfile, secret: String?) async throws -> [String] {
        switch profile.provider {
        case .anthropic: return try await fetchAnthropicStyle(profile: profile, secret: secret)
        case .openai:    return try await fetchOpenAIStyle(profile: profile, secret: secret)
        case .ollama:    return try await fetchOllamaStyle(profile: profile, secret: secret)
        }
    }

    // MARK: - Anthropic-compatible: GET <base>/v1/models

    private static func fetchAnthropicStyle(profile: ConnectionProfile, secret: String?) async throws -> [String] {
        guard let url = URL(string: "\(profile.normalizedBaseURL)/v1/models") else {
            throw err("Ungültige URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        applyAuth(to: &request, profile: profile, secret: secret)
        if profile.sendAnthropicVersion {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }

        let (data, response) = try await performRequest(request)
        try throwIfNotOK(response: response, data: data)

        struct AnthropicModels: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        let decoded = try JSONDecoder().decode(AnthropicModels.self, from: data)
        return decoded.data.map { $0.id }.sorted()
    }

    // MARK: - OpenAI-compatible: GET <base>/v1/models

    private static func fetchOpenAIStyle(profile: ConnectionProfile, secret: String?) async throws -> [String] {
        guard let url = URL(string: "\(profile.normalizedBaseURL)/v1/models") else {
            throw err("Ungültige URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        applyAuth(to: &request, profile: profile, secret: secret)

        let (data, response) = try await performRequest(request)
        try throwIfNotOK(response: response, data: data)

        struct OpenAIModels: Decodable {
            struct Entry: Decodable { let id: String }
            let data: [Entry]
        }
        let decoded = try JSONDecoder().decode(OpenAIModels.self, from: data)
        return decoded.data.map { $0.id }.sorted()
    }

    // MARK: - Ollama: GET <base>/api/tags

    private static func fetchOllamaStyle(profile: ConnectionProfile, secret: String?) async throws -> [String] {
        guard let url = URL(string: "\(profile.normalizedBaseURL)/api/tags") else {
            throw err("Ungültige URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 5
        if profile.authScheme == .bearer, let secret, !secret.isEmpty {
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await performRequest(request)
        try throwIfNotOK(response: response, data: data)

        struct OllamaTags: Decodable {
            struct Entry: Decodable { let name: String }
            let models: [Entry]
        }
        let decoded = try JSONDecoder().decode(OllamaTags.self, from: data)
        return decoded.models.map { $0.name }.sorted()
    }

    // MARK: - Helpers

    private static func applyAuth(to request: inout URLRequest,
                                  profile: ConnectionProfile,
                                  secret: String?) {
        guard let secret, !secret.isEmpty else { return }
        switch profile.authScheme {
        case .apiKey:
            request.setValue(secret, forHTTPHeaderField: "x-api-key")
        case .bearer:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .none:
            break
        }
    }

    private static func performRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await URLSession.shared.data(for: request)
        } catch {
            throw err("Endpoint nicht erreichbar")
        }
    }

    private static func throwIfNotOK(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw err("Unerwartete Antwort")
        }
        guard (200..<300).contains(http.statusCode) else {
            switch http.statusCode {
            case 401, 403: throw err("Authentifizierung fehlgeschlagen")
            case 404:      throw err("Endpoint unterstützt Modell-Liste nicht")
            default:       throw err("HTTP \(http.statusCode)")
            }
        }
    }

    private static func err(_ message: String) -> NSError {
        NSError(domain: "ModelDiscovery", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }
}
