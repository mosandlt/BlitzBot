import Foundation

/// Touches every known Keychain item once at launch so any ACL prompts fire early
/// (at a predictable moment) instead of mid-recording.
///
/// Migration: items found in the legacy login keychain (created before v1.1.0) are
/// moved to the Data Protection keychain. Once migrated, macOS never prompts for them
/// again — the Data Protection keychain uses no per-app ACLs.
enum KeychainPreWarmer {
    static func prewarm(profileStore: ProfileStore) {
        DispatchQueue.global(qos: .utility).async {
            var touched = 0
            var migrated = 0

            // Legacy per-provider slots (pre-profile era)
            let legacy = [
                "anthropic-api-key",
                KeychainStore.openAIAccount,
                KeychainStore.ollamaAccount
            ]
            for account in legacy {
                touched += 1
                if let existing = KeychainStore.loadKey(account: account) {
                    // Re-save: if item was in legacy keychain, this migrates it to
                    // Data Protection keychain — future reads are completely silent.
                    KeychainStore.migrateToDataProtection(key: existing, account: account)
                    migrated += 1
                }
            }

            // Per-profile slots
            for profile in profileStore.profiles {
                touched += 1
                if let existing = KeychainStore.loadKey(account: profile.keychainAccount) {
                    KeychainStore.migrateToDataProtection(key: existing, account: profile.keychainAccount)
                    migrated += 1
                }
            }

            Log.write("Keychain prewarm: \(migrated)/\(touched) items migrated to Data Protection keychain")
        }
    }
}
