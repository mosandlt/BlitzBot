import Foundation

enum AppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }
    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }
    static var versionLabel: String { "v\(version) (\(build))" }
    static let repoURL = URL(string: "https://github.com/mosandlt/BlitzBot")!
    static let releasesAPI = URL(string: "https://api.github.com/repos/mosandlt/BlitzBot/releases/latest")!
}
