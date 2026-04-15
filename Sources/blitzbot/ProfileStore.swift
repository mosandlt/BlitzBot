import Foundation

/// Persisted registry of connection profiles, with active-profile selection and
/// per-profile Keychain-backed secrets.
///
/// Storage layout:
///   - UserDefaults["connectionProfiles"]  — JSON-encoded [ConnectionProfile]
///   - UserDefaults["activeProfileID"]     — UUID string, or absent
///   - Keychain account "profile-<uuid>"   — per-profile secret
final class ProfileStore: ObservableObject {
    @Published private(set) var profiles: [ConnectionProfile] = []
    @Published var activeProfileID: UUID? {
        didSet { persistActiveID() }
    }

    private let defaults: UserDefaults
    private static let profilesKey = "connectionProfiles"
    private static let activeKey = "activeProfileID"
    private static let migrationKey = "profilesMigration.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        loadFromDisk()
        if !defaults.bool(forKey: Self.migrationKey) {
            migrateFromLegacyIfNeeded()
            defaults.set(true, forKey: Self.migrationKey)
        }
    }

    // MARK: - Queries

    func profile(id: UUID) -> ConnectionProfile? {
        profiles.first { $0.id == id }
    }

    var activeProfile: ConnectionProfile? {
        guard let id = activeProfileID else { return nil }
        return profile(id: id)
    }

    /// Secret (API key / bearer token) for a profile, or nil if unset.
    func secret(for profile: ConnectionProfile) -> String? {
        KeychainStore.loadKey(account: profile.keychainAccount)
    }

    // MARK: - Mutations

    func add(_ profile: ConnectionProfile, secret: String?) throws {
        profiles.append(profile)
        persistProfiles()
        if let secret, !secret.isEmpty {
            try KeychainStore.saveKey(secret, account: profile.keychainAccount)
        }
        if activeProfileID == nil {
            activeProfileID = profile.id
        }
    }

    func update(_ profile: ConnectionProfile, secret: String? = nil, clearSecret: Bool = false) throws {
        guard let idx = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[idx] = profile
        persistProfiles()
        if clearSecret {
            KeychainStore.deleteKey(account: profile.keychainAccount)
        } else if let secret, !secret.isEmpty {
            try KeychainStore.saveKey(secret, account: profile.keychainAccount)
        }
    }

    func delete(_ id: UUID) {
        guard let profile = profile(id: id) else { return }
        KeychainStore.deleteKey(account: profile.keychainAccount)
        profiles.removeAll { $0.id == id }
        persistProfiles()
        if activeProfileID == id {
            activeProfileID = profiles.first?.id
        }
    }

    func setActive(_ id: UUID) {
        guard profiles.contains(where: { $0.id == id }) else { return }
        activeProfileID = id
    }

    // MARK: - Persistence

    private func loadFromDisk() {
        if let data = defaults.data(forKey: Self.profilesKey),
           let decoded = try? JSONDecoder().decode([ConnectionProfile].self, from: data) {
            profiles = decoded
        }
        if let raw = defaults.string(forKey: Self.activeKey),
           let uuid = UUID(uuidString: raw) {
            activeProfileID = uuid
        }
    }

    private func persistProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            defaults.set(data, forKey: Self.profilesKey)
        }
    }

    private func persistActiveID() {
        if let id = activeProfileID {
            defaults.set(id.uuidString, forKey: Self.activeKey)
        } else {
            defaults.removeObject(forKey: Self.activeKey)
        }
    }

    // MARK: - Migration

    /// On first launch after the profiles feature ships, seed profiles from legacy
    /// per-provider settings so existing users keep working without reconfiguration.
    private func migrateFromLegacyIfNeeded() {
        guard profiles.isEmpty else { return }

        var seeded: [ConnectionProfile] = []
        var copiedSecrets: [(UUID, String)] = []

        if let key = KeychainStore.loadAPIKey(), !key.isEmpty {
            let model = defaults.string(forKey: "claudeModel")
            let p = ConnectionProfile(name: "Anthropic", provider: .anthropic, preferredModel: model)
            seeded.append(p)
            copiedSecrets.append((p.id, key))
        }
        if let key = KeychainStore.loadOpenAIKey(), !key.isEmpty {
            let model = defaults.string(forKey: "openaiModel")
            let p = ConnectionProfile(name: "OpenAI", provider: .openai, preferredModel: model)
            seeded.append(p)
            copiedSecrets.append((p.id, key))
        }
        let ollamaURL = defaults.string(forKey: "ollamaBaseURL")
        let ollamaModel = defaults.string(forKey: "ollamaModel")
        if ollamaURL != nil || ollamaModel != nil {
            let ollamaKey = KeychainStore.loadOllamaKey()
            let p = ConnectionProfile(name: "Ollama",
                                      provider: .ollama,
                                      baseURL: ollamaURL,
                                      preferredModel: ollamaModel)
            seeded.append(p)
            if let k = ollamaKey, !k.isEmpty { copiedSecrets.append((p.id, k)) }
        }

        guard !seeded.isEmpty else {
            Log.write("ProfileStore: nothing to migrate")
            return
        }

        profiles = seeded
        persistProfiles()
        for (id, secret) in copiedSecrets {
            if let p = profile(id: id) {
                try? KeychainStore.saveKey(secret, account: p.keychainAccount)
            }
        }

        // Pick active based on the last-used legacy provider.
        if let raw = defaults.string(forKey: "llmProvider"),
           let provider = LLMProvider(rawValue: raw),
           let match = seeded.first(where: { $0.provider == provider }) {
            activeProfileID = match.id
        } else {
            activeProfileID = seeded.first?.id
        }

        Log.write("ProfileStore: migrated \(seeded.count) profile(s) from legacy settings")
    }

    // MARK: - Import / Export

    func importFromJSON(_ data: Data) throws -> ConnectionProfile {
        let decoded = try JSONDecoder().decode(ConnectionProfileImport.self, from: data)
        guard let provider = LLMProvider(rawValue: decoded.provider) else {
            throw NSError(domain: "ProfileStore", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Unbekannter Provider: \(decoded.provider)"])
        }
        let scheme = decoded.authScheme.flatMap(AuthScheme.init(rawValue:))
        let profile = ConnectionProfile(
            name: decoded.name.isEmpty ? "Imported" : decoded.name,
            provider: provider,
            baseURL: decoded.baseURL,
            authScheme: scheme,
            preferredModel: decoded.preferredModel,
            sendAnthropicVersion: decoded.sendAnthropicVersion
        )
        try add(profile, secret: decoded.apiKey)
        return profile
    }

    /// Exports a profile to JSON. Secrets are never included.
    func exportJSON(for profile: ConnectionProfile) throws -> Data {
        let payload = ConnectionProfileImport(
            name: profile.name,
            provider: profile.provider.rawValue,
            baseURL: profile.baseURL,
            authScheme: profile.authScheme.rawValue,
            preferredModel: profile.preferredModel,
            sendAnthropicVersion: profile.sendAnthropicVersion,
            apiKey: nil
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(payload)
    }
}
