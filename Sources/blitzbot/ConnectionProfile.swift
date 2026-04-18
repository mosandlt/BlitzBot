import Foundation

/// Authentication scheme for outbound LLM requests.
enum AuthScheme: String, Codable, CaseIterable, Identifiable {
    case apiKey   // Anthropic-style header: `x-api-key: <key>`
    case bearer   // Authorization: Bearer <token>
    case none     // No auth (e.g. local Ollama)

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .apiKey: return "API Key (x-api-key)"
        case .bearer: return "Bearer Token"
        case .none:   return "Ohne Authentifizierung"
        }
    }
}

/// A user-defined LLM connection profile.
///
/// Decouples provider family (what API schema to speak) from endpoint, auth, and model.
/// Same provider can have multiple profiles (e.g. different accounts, different custom endpoints).
struct ConnectionProfile: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var provider: LLMProvider
    var baseURL: String
    var authScheme: AuthScheme
    var preferredModel: String?
    /// Anthropic-schema endpoints accept (and sometimes require) an `anthropic-version` header.
    /// For gateways that set it themselves, disable it to avoid version mismatch errors.
    var sendAnthropicVersion: Bool

    init(id: UUID = UUID(),
         name: String,
         provider: LLMProvider,
         baseURL: String? = nil,
         authScheme: AuthScheme? = nil,
         preferredModel: String? = nil,
         sendAnthropicVersion: Bool? = nil) {
        self.id = id
        self.name = name
        self.provider = provider
        self.baseURL = baseURL ?? Self.defaultBaseURL(for: provider)
        self.authScheme = authScheme ?? Self.defaultAuthScheme(for: provider)
        self.preferredModel = preferredModel
        self.sendAnthropicVersion = sendAnthropicVersion ?? (provider == .anthropic)
    }

    static func defaultBaseURL(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic:         return "https://api.anthropic.com"
        case .openai:            return "https://api.openai.com"
        case .ollama:            return "http://localhost:11434"
        case .appleIntelligence: return ""   // on-device; no URL
        }
    }

    static func defaultAuthScheme(for provider: LLMProvider) -> AuthScheme {
        switch provider {
        case .anthropic:         return .apiKey
        case .openai:            return .bearer
        case .ollama:            return .none
        case .appleIntelligence: return .none
        }
    }

    /// Normalized base URL (trailing slash stripped).
    var normalizedBaseURL: String {
        var url = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while url.hasSuffix("/") { url.removeLast() }
        return url
    }

    /// Keychain account slot for this profile's secret.
    var keychainAccount: String { "profile-\(id.uuidString)" }
}

/// JSON schema used for import/export.
///
/// Deliberately minimal; does NOT include the secret. Secrets live only in Keychain.
/// If an imported file contains an `apiKey` field, it's applied once and never re-exported.
struct ConnectionProfileImport: Codable {
    var name: String
    var provider: String            // LLMProvider raw
    var baseURL: String?
    var authScheme: String?         // AuthScheme raw
    var preferredModel: String?
    var sendAnthropicVersion: Bool?
    var apiKey: String?             // optional — stripped after import
}
