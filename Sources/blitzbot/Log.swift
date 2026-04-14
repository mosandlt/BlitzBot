import Foundation

enum Log {
    static let url: URL = {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".blitzbot/logs", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("blitzbot.log")
    }()

    static func write(_ line: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        let full = "[\(ts)] \(line)\n"
        if let data = full.data(using: .utf8) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data)
                try? handle.close()
            } else {
                try? data.write(to: url)
            }
        }
        FileHandle.standardError.write(Data(full.utf8))
    }
}
