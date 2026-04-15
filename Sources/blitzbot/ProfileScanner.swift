import Foundation

/// A profile candidate discovered by scanning well-known local config paths.
struct DiscoveredProfile: Identifiable, Hashable {
    let id = UUID()
    let suggestedName: String
    let provider: LLMProvider
    let baseURL: String
    let authScheme: AuthScheme
    let preferredModel: String?
    let sendAnthropicVersion: Bool
    let secret: String?
    /// Absolute path of the source file — shown to the user so they can verify before import.
    let sourcePath: String

    func makeProfile() -> ConnectionProfile {
        ConnectionProfile(
            name: suggestedName,
            provider: provider,
            baseURL: baseURL,
            authScheme: authScheme,
            preferredModel: preferredModel,
            sendAnthropicVersion: sendAnthropicVersion
        )
    }
}

/// Scans a small set of well-known local config directories for things that look
/// like LLM connection profiles. Parses locally, never transmits anything.
enum ProfileScanner {
    /// Paths (relative to the home directory) that are inspected.
    static let inspectedRelativePaths: [String] = [
        ".claude-profiles",
        ".claude/settings.json",
        ".config/claude"
    ]

    static func scan() -> [DiscoveredProfile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        var results: [DiscoveredProfile] = []

        // 1) Directory: ~/.claude-profiles/*.json  (user-managed profile snapshots)
        //    Accepts both "name.settings.json" and plain "name.json".
        let profilesDir = home.appendingPathComponent(".claude-profiles")
        if let files = try? FileManager.default.contentsOfDirectory(at: profilesDir,
                                                                    includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                let lastName = file.lastPathComponent
                // Strip .settings.json first, then fall back to stripping plain .json
                let base: String
                if lastName.hasSuffix(".settings.json") {
                    base = String(lastName.dropLast(".settings.json".count))
                } else {
                    base = file.deletingPathExtension().lastPathComponent
                }
                if let discovered = parseClaudeSettings(at: file, suggestedName: base) {
                    results.append(discovered)
                }
            }
        }

        // 2) Single file: ~/.claude/settings.json
        let mainSettings = home.appendingPathComponent(".claude/settings.json")
        if FileManager.default.fileExists(atPath: mainSettings.path) {
            if let discovered = parseClaudeSettings(at: mainSettings, suggestedName: "Claude Code") {
                results.append(discovered)
            }
        }

        // 3) Directory: ~/.config/claude/*.json
        let configDir = home.appendingPathComponent(".config/claude")
        if let files = try? FileManager.default.contentsOfDirectory(at: configDir,
                                                                    includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                let base = file.deletingPathExtension().lastPathComponent
                if let discovered = parseClaudeSettings(at: file, suggestedName: base) {
                    results.append(discovered)
                }
            }
        }

        // Deduplicate identical (baseURL, secret) pairs — a user often backs up the same config
        // under multiple names.
        var seen: Set<String> = []
        return results.filter { candidate in
            let key = "\(candidate.baseURL)|\(candidate.secret ?? "")"
            if seen.contains(key) { return false }
            seen.insert(key)
            return true
        }
    }

    // MARK: - Claude Code settings schema
    //
    // Claude Code stores env-style configuration under `env`, e.g.:
    //   { "env": { "ANTHROPIC_BASE_URL": "...", "ANTHROPIC_AUTH_TOKEN": "..." } }
    // That's the de-facto interchange format we can lift into a blitzbot profile.
    private static func parseClaudeSettings(at url: URL, suggestedName: String) -> DiscoveredProfile? {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        let env = json["env"] as? [String: Any] ?? [:]

        let baseURL = (env["ANTHROPIC_BASE_URL"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let authToken = (env["ANTHROPIC_AUTH_TOKEN"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let apiKey = (env["ANTHROPIC_API_KEY"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        let model = (env["ANTHROPIC_MODEL"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        // Only offer a candidate when there's *something* to import. An empty settings file
        // (no env overrides) isn't useful.
        guard baseURL != nil || authToken != nil || apiKey != nil else { return nil }

        // Heuristic: if an AUTH_TOKEN is present, assume a gateway that wants Bearer auth and
        // that handles the anthropic-version header itself. If only API_KEY is set, assume
        // direct Anthropic API with x-api-key.
        let (authScheme, secret, sendVersion): (AuthScheme, String?, Bool)
        if let t = authToken {
            authScheme = .bearer
            secret = t
            sendVersion = false
        } else if let k = apiKey {
            authScheme = .apiKey
            secret = k
            sendVersion = true
        } else {
            authScheme = .apiKey
            secret = nil
            sendVersion = true
        }

        return DiscoveredProfile(
            suggestedName: suggestedName,
            provider: .anthropic,
            baseURL: baseURL ?? ConnectionProfile.defaultBaseURL(for: .anthropic),
            authScheme: authScheme,
            preferredModel: model,
            sendAnthropicVersion: sendVersion,
            secret: secret,
            sourcePath: url.path
        )
    }
}
