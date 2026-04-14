import Foundation

struct WhisperTranscriber {
    var binaryPath: String
    var modelPath: String
    var language: String = "auto"
    var vocabularyPrompt: String = ""

    struct Result {
        let text: String
        let detectedLanguage: String
    }

    func transcribe(audioURL: URL) throws -> Result {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        let basePath = audioURL.deletingPathExtension().path
        var args: [String] = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", language,
            "-nt",
            "--no-prints",
            "-otxt",
            "-oj",
            "-of", basePath
        ]
        if !vocabularyPrompt.isEmpty {
            args += ["--prompt", vocabularyPrompt]
        }
        process.arguments = args

        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err

        try process.run()
        process.waitUntilExit()

        let txtURL = URL(fileURLWithPath: basePath + ".txt")
        let jsonURL = URL(fileURLWithPath: basePath + ".json")
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: txtURL)
            try? FileManager.default.removeItem(at: jsonURL)
        }

        if process.terminationStatus != 0 {
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "Whisper", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "whisper-cli Fehler: \(msg)"])
        }

        let text = (try? String(contentsOf: txtURL, encoding: .utf8)) ?? ""
        let detectedLanguage = parseDetectedLanguage(jsonURL: jsonURL) ?? language
        return Result(
            text: text.trimmingCharacters(in: .whitespacesAndNewlines),
            detectedLanguage: detectedLanguage
        )
    }

    private func parseDetectedLanguage(jsonURL: URL) -> String? {
        guard let data = try? Data(contentsOf: jsonURL),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let result = root["result"] as? [String: Any],
           let lang = result["language"] as? String {
            return lang
        }
        if let params = root["params"] as? [String: Any],
           let lang = params["language"] as? String {
            return lang
        }
        return nil
    }
}
