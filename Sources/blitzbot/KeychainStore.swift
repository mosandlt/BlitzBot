import Foundation
import Security

enum KeychainStore {
    private static let service = "de.blitzbot.mac"
    private static let account = "anthropic-api-key"
    static let openAIAccount = "openai-api-key"
    static let ollamaAccount = "ollama-api-key"

    // MARK: - Anthropic (default / legacy API)

    static func saveAPIKey(_ key: String) throws {
        try saveKey(key, account: account)
    }

    static func loadAPIKey() -> String? {
        loadKey(account: account)
    }

    static func deleteAPIKey() {
        deleteKey(account: account)
    }

    // MARK: - Generic per-account helpers

    static func saveKey(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    static func loadKey(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    static func deleteKey(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }

    // MARK: - Convenience accessors per provider

    static func saveOpenAIKey(_ key: String) throws { try saveKey(key, account: openAIAccount) }
    static func loadOpenAIKey() -> String? { loadKey(account: openAIAccount) }
    static func deleteOpenAIKey() { deleteKey(account: openAIAccount) }

    static func saveOllamaKey(_ key: String) throws { try saveKey(key, account: ollamaAccount) }
    static func loadOllamaKey() -> String? { loadKey(account: ollamaAccount) }
    static func deleteOllamaKey() { deleteKey(account: ollamaAccount) }
}
