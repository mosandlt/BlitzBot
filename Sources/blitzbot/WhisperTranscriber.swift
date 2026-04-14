import Foundation

struct WhisperTranscriber {
    var binaryPath: String
    var modelPath: String
    var language: String = "de"
    var vocabularyPrompt: String = ""

    func transcribe(audioURL: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        var args: [String] = [
            "-m", modelPath,
            "-f", audioURL.path,
            "-l", language,
            "-nt",
            "--no-prints",
            "-otxt",
            "-of", audioURL.deletingPathExtension().path
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

        let txtURL = audioURL.deletingPathExtension().appendingPathExtension("txt")
        defer {
            try? FileManager.default.removeItem(at: audioURL)
            try? FileManager.default.removeItem(at: txtURL)
        }

        if process.terminationStatus != 0 {
            let errData = err.fileHandleForReading.readDataToEndOfFile()
            let msg = String(data: errData, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "Whisper", code: Int(process.terminationStatus),
                          userInfo: [NSLocalizedDescriptionKey: "whisper-cli Fehler: \(msg)"])
        }

        let text = (try? String(contentsOf: txtURL, encoding: .utf8)) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
