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

    /// Saves a secret. New items always go into the Data Protection keychain
    /// (kSecUseDataProtectionKeychain = true) which does **not** use per-app ACLs —
    /// so macOS never shows the "Allow / Always Allow" password dialog for them.
    ///
    /// Update path: tries the Data Protection keychain first, then the legacy login
    /// keychain (for items created before this version). Updating in place preserves
    /// whatever ACL the existing item has, avoiding the prompt for items that were
    /// already "Always Allowed".
    static func saveKey(_ key: String, account: String) throws {
        let data = Data(key.utf8)

        // ── 1. Try update in Data Protection keychain (ideal path)
        let dpQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecUseDataProtectionKeychain as String: true
        ]
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(dpQuery as CFDictionary, updateAttrs as CFDictionary) == errSecSuccess {
            return
        }

        // ── 2. Try update in legacy login keychain (items from older versions)
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        if SecItemUpdate(legacyQuery as CFDictionary, updateAttrs as CFDictionary) == errSecSuccess {
            return
        }

        // ── 3. Item doesn't exist yet — create in Data Protection keychain (no ACL prompt ever)
        var addAttrs = dpQuery
        addAttrs[kSecValueData as String] = data
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        let status = SecItemAdd(addAttrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    /// Reads a secret. Checks the Data Protection keychain first, then falls back
    /// to the legacy login keychain so older items still work during migration.
    static func loadKey(account: String) -> String? {
        // ── Data Protection keychain (no prompt)
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseDataProtectionKeychain as String: true
        ]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
           let data = item as? Data,
           let key = String(data: data, encoding: .utf8) {
            return key
        }

        // ── Legacy login keychain fallback (may show "Allow" prompt if not yet ACL-allowed)
        query.removeValue(forKey: kSecUseDataProtectionKeychain as String)
        item = nil
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }
        return key
    }

    static func deleteKey(account: String) {
        // Delete from both keychains in case the item exists in either.
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        var dp = base
        dp[kSecUseDataProtectionKeychain as String] = true
        SecItemDelete(dp as CFDictionary)
        SecItemDelete(base as CFDictionary)
    }

    /// Migrates an item from the legacy login keychain to the Data Protection keychain.
    /// Called by KeychainPreWarmer after a successful read. Once migrated, the item
    /// lives in the Data Protection partition and never prompts again.
    static func migrateToDataProtection(key: String, account: String) {
        // Delete from legacy keychain first.
        let legacyQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(legacyQuery as CFDictionary)

        // Add to Data Protection keychain.
        let data = Data(key.utf8)
        let addAttrs: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock,
            kSecUseDataProtectionKeychain as String: true
        ]
        SecItemAdd(addAttrs as CFDictionary, nil)
    }

    // MARK: - Convenience accessors per provider

    static func saveOpenAIKey(_ key: String) throws { try saveKey(key, account: openAIAccount) }
    static func loadOpenAIKey() -> String? { loadKey(account: openAIAccount) }
    static func deleteOpenAIKey() { deleteKey(account: openAIAccount) }

    static func saveOllamaKey(_ key: String) throws { try saveKey(key, account: ollamaAccount) }
    static func loadOllamaKey() -> String? { loadKey(account: ollamaAccount) }
    static func deleteOllamaKey() { deleteKey(account: ollamaAccount) }
}
