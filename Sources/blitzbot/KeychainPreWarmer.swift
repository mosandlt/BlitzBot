import Foundation

/// Rewrites every known Keychain item with an open-access ACL.
///
/// Open-access ACL (SecAccessCreate with empty trustedApps array) means any application
/// can read the item without a confirmation dialog — no CDHash dependency, no prompts
/// after rebuilds.
///
/// Strategy:
///  - Legacy accounts (anthropic-api-key, openai-api-key, ollama-api-key) are rewritten
///    exactly once (guarded by `migratedKey`).
///  - Profile accounts are checked at every launch against a persisted set of already-
///    migrated UUIDs. New profiles added after the initial migration are patched on the
///    next launch without triggering the full one-time migration again.
enum KeychainPreWarmer {
    private static let migratedKey      = "keychain.openACL.migrated.v2"
    private static let migratedProfiles = "keychain.openACL.migratedProfiles"

    static func prewarm(profileStore: ProfileStore) {
        let defaults = UserDefaults.standard
        let legacyDone = defaults.bool(forKey: migratedKey)

        // Accounts that need rewriting this launch.
        var accountsToMigrate: [String] = []

        // 1. Legacy accounts — only on first run.
        if !legacyDone {
            accountsToMigrate += [
                "anthropic-api-key",
                KeychainStore.openAIAccount,
                KeychainStore.ollamaAccount
            ]
        }

        // 2. Profile accounts — always check for new ones not yet migrated.
        let alreadyMigrated = Set(defaults.stringArray(forKey: migratedProfiles) ?? [])
        let profileAccounts = profileStore.profiles.map { $0.keychainAccount }
        let newProfileAccounts = profileAccounts.filter { !alreadyMigrated.contains($0) }
        accountsToMigrate += newProfileAccounts

        if accountsToMigrate.isEmpty {
            Log.write("Keychain prewarm: open-ACL migration already done, skipping")
            return
        }

        DispatchQueue.global(qos: .utility).async {
            var migrated = 0
            for account in accountsToMigrate {
                if KeychainStore.rewriteWithOpenAccess(account: account) {
                    migrated += 1
                }
            }

            DispatchQueue.main.async {
                if !legacyDone {
                    defaults.set(true, forKey: migratedKey)
                }
                if !newProfileAccounts.isEmpty {
                    let updated = Array(alreadyMigrated.union(newProfileAccounts))
                    defaults.set(updated, forKey: migratedProfiles)
                }
                Log.write("Keychain prewarm: \(migrated)/\(accountsToMigrate.count) items rewritten with open-access ACL")
            }
        }
    }
}
