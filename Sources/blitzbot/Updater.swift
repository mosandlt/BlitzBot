import AppKit
import Foundation

@MainActor
final class Updater: ObservableObject {
    enum State {
        case idle
        case checking
        case upToDate
        case available(version: String, url: URL, notes: String)
        case downloading(progress: Double)
        case ready(appURL: URL)
        case error(String)
    }

    @Published var state: State = .idle

    private struct Release: Decodable {
        let tag_name: String
        let name: String?
        let body: String?
        let assets: [Asset]
        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    func checkForUpdates() async {
        state = .checking
        do {
            var req = URLRequest(url: AppInfo.releasesAPI)
            req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                state = .upToDate
                return
            }
            let release = try JSONDecoder().decode(Release.self, from: data)
            let remote = release.tag_name.trimmingCharacters(in: CharacterSet(charactersIn: "v"))
            if compareSemver(remote, AppInfo.version) <= 0 {
                state = .upToDate
                return
            }
            guard let zip = release.assets.first(where: { $0.name.hasSuffix(".zip") }),
                  let url = URL(string: zip.browser_download_url) else {
                state = .error("Kein .zip-Asset im Release gefunden")
                return
            }
            state = .available(version: remote, url: url, notes: release.body ?? "")
            Log.write("Update available: \(remote)")
        } catch {
            Log.write("Update check failed: \(error)")
            state = .error(error.localizedDescription)
        }
    }

    func download() async {
        guard case let .available(version, url, _) = state else { return }
        state = .downloading(progress: 0)
        do {
            let (fileURL, _) = try await URLSession.shared.download(from: url)
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("blitzbot-update-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)

            let zipDest = tmp.appendingPathComponent("blitzbot-\(version).zip")
            try? FileManager.default.removeItem(at: zipDest)
            try FileManager.default.moveItem(at: fileURL, to: zipDest)

            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
            unzip.arguments = ["-q", zipDest.path, "-d", tmp.path]
            try unzip.run()
            unzip.waitUntilExit()
            guard unzip.terminationStatus == 0 else {
                state = .error("Entpacken fehlgeschlagen")
                return
            }

            guard let appURL = try findApp(in: tmp) else {
                state = .error("blitzbot.app nicht in Release")
                return
            }
            state = .ready(appURL: appURL)
            Log.write("Update downloaded: \(appURL.path)")
        } catch {
            Log.write("Update download failed: \(error)")
            state = .error(error.localizedDescription)
        }
    }

    func installAndRelaunch() {
        guard case let .ready(newApp) = state else { return }
        let currentApp = Bundle.main.bundleURL
        let script = """
        sleep 1
        rm -rf "\(currentApp.path).bak"
        mv "\(currentApp.path)" "\(currentApp.path).bak"
        cp -R "\(newApp.path)" "\(currentApp.path)"
        rm -rf "\(currentApp.path).bak"
        open "\(currentApp.path)"
        """
        let scriptURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("blitzbot-installer-\(UUID().uuidString).sh")
        try? script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/bin/bash")
        proc.arguments = [scriptURL.path]
        try? proc.run()

        NSApplication.shared.terminate(nil)
    }

    private func findApp(in dir: URL) throws -> URL? {
        let contents = try FileManager.default.contentsOfDirectory(at: dir,
            includingPropertiesForKeys: nil)
        for url in contents {
            if url.pathExtension == "app" { return url }
            var isDir: ObjCBool = false
            FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue, let nested = try findApp(in: url) { return nested }
        }
        return nil
    }

    private func compareSemver(_ a: String, _ b: String) -> Int {
        let ap = a.split(separator: ".").compactMap { Int($0) }
        let bp = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(ap.count, bp.count) {
            let av = i < ap.count ? ap[i] : 0
            let bv = i < bp.count ? bp[i] : 0
            if av != bv { return av - bv }
        }
        return 0
    }
}
