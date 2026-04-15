import Foundation

/// Rewrites every known Keychain item with an open-access ACL exactly once.
///
/// Open-access ACL (SecAccessCreate with empty trustedApps array) means any application
/// can read the item without a confirmation dialog — no CDHash dependency, no prompts
/// after rebuilds. The migration runs once and sets a UserDefaults flag so it is never
/// repeated.
enum KeychainPreWarmer {
    private static let migratedKey = "keychain.openACL.migrated"

    static func prewarm(profileStore: ProfileStore) {
        guard !UserDefaults.standard.bool(forKey: migratedKey) else {
            Log.write("Keychain prewarm: open-ACL migration already done, skipping")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            let allAccounts = [
                "anthropic-api-key",
                KeychainStore.openAIAccount,
                KeychainStore.ollamaAccount
            ] + profileStore.profiles.map { $0.keychainAccount }

            var migrated = 0
            for account in allAccounts {
                if KeychainStore.rewriteWithOpenAccess(account: account) {
                    migrated += 1
                }
            }

            DispatchQueue.main.async {
                UserDefaults.standard.set(true, forKey: migratedKey)
            }
            Log.write("Keychain prewarm: \(migrated)/\(allAccounts.count) items rewritten with open-access ACL — will not run again")
        }
    }
}
