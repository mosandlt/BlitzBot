import Foundation
import Security

enum KeychainStore {
    private static let service = "de.blitzbot.mac"
    private static let account = "anthropic-api-key"
    static let openAIAccount = "openai-api-key"
    static let ollamaAccount = "ollama-api-key"

    // MARK: - Anthropic (default / legacy API)

    static func saveAPIKey(_ key: String) throws { try saveKey(key, account: account) }
    static func loadAPIKey() -> String? { loadKey(account: account) }
    static func deleteAPIKey() { deleteKey(account: account) }

    // MARK: - Generic per-account helpers

    /// Saves a secret. New items are created with an open-access ACL so macOS never
    /// shows a password confirmation dialog, regardless of the app's CDHash.
    /// Updates preserve the existing ACL (which may already be "Always Allow").
    static func saveKey(_ key: String, account: String) throws {
        let data = Data(key.utf8)
        let lookup: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        // Try update first — preserves existing ACL, no dialog regardless of CDHash changes.
        let updateAttrs: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        if SecItemUpdate(lookup as CFDictionary, updateAttrs as CFDictionary) == errSecSuccess {
            return
        }

        // New item — create with open-access ACL: empty trustedApps array means
        // any application can read this item without a confirmation dialog.
        var addAttrs = lookup
        addAttrs[kSecValueData as String] = data
        addAttrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        if let access = makeOpenAccess() {
            addAttrs[kSecAttrAccess as String] = access
        }
        let status = SecItemAdd(addAttrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    static func loadKey(account: String) -> String? {
        // Primary: search login keychain (open-access ACL items live here)
        if let key = loadKeyRaw(account: account, extraAttrs: [:]) { return key }
        // Fallback: items that a previous version moved to Data Protection keychain
        if let key = loadKeyRaw(account: account,
                                extraAttrs: [kSecUseDataProtectionKeychain as String: true]) {
            return key
        }
        return nil
    }

    private static func loadKeyRaw(account: String, extraAttrs: [String: Any]) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        extraAttrs.forEach { query[$0.key] = $0.value }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8) else { return nil }
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

    /// Rewrites an existing keychain item in-place with an open-access ACL.
    /// Called by KeychainPreWarmer for the one-time migration of legacy items.
    static func rewriteWithOpenAccess(account: String) -> Bool {
        guard let key = loadKey(account: account) else { return false }
        deleteKey(account: account)
        guard (try? saveKey(key, account: account)) != nil else { return false }
        return true
    }

    // MARK: - Open-access ACL

    /// Returns a SecAccess that allows any application to use the item without
    /// a confirmation dialog. Passing an empty array (not nil) to SecAccessCreate
    /// means "no restrictions — all apps allowed". Nil would mean "current app only".
    private static func makeOpenAccess() -> SecAccess? {
        var accessRef: SecAccess?
        let emptyList = [] as CFArray        // empty = unrestricted access
        let status = SecAccessCreate("blitzbot keychain item" as CFString,
                                     emptyList, &accessRef)
        return status == errSecSuccess ? accessRef : nil
    }

    // MARK: - Convenience accessors per provider

    static func saveOpenAIKey(_ key: String) throws { try saveKey(key, account: openAIAccount) }
    static func loadOpenAIKey() -> String? { loadKey(account: openAIAccount) }
    static func deleteOpenAIKey() { deleteKey(account: openAIAccount) }

    static func saveOllamaKey(_ key: String) throws { try saveKey(key, account: ollamaAccount) }
    static func loadOllamaKey() -> String? { loadKey(account: ollamaAccount) }
    static func deleteOllamaKey() { deleteKey(account: ollamaAccount) }
}
