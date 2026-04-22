import Foundation

/// Curated list of multilingual Whisper models hosted by ggerganov on HuggingFace.
/// English-only variants are intentionally omitted because blitzbot supports DE/EN
/// out of the box.
enum WhisperModel: String, CaseIterable, Identifiable {
    case base               = "ggml-base"
    case small              = "ggml-small"
    case medium             = "ggml-medium"
    case largeV3TurboQ5     = "ggml-large-v3-turbo-q5_0"
    case largeV3Turbo       = "ggml-large-v3-turbo"
    case largeV3            = "ggml-large-v3"

    var id: String { rawValue }

    var filename: String { "\(rawValue).bin" }

    /// Approximate on-disk size in MB. Used for the progress label and the
    /// size-sanity check after download (we accept anything ≥ 80% of expected).
    var sizeMB: Int {
        switch self {
        case .base:           return 148
        case .small:          return 488
        case .medium:         return 1530
        case .largeV3TurboQ5: return 574
        case .largeV3Turbo:   return 1620
        case .largeV3:        return 3094
        }
    }

    var displayName: String {
        switch self {
        case .base:           return "Base"
        case .small:          return "Small"
        case .medium:         return "Medium"
        case .largeV3TurboQ5: return "Large v3 Turbo (Q5 quantized)"
        case .largeV3Turbo:   return "Large v3 Turbo"
        case .largeV3:        return "Large v3"
        }
    }

    /// One-liner shown under the picker option — speed, quality, footprint.
    var subtitle: String {
        switch self {
        case .base:           return "Sehr schnell, ungenau bei Akzent oder Fachsprache"
        case .small:          return "Schnell, brauchbar für klare Diktate"
        case .medium:         return "Solide Mitte, etwas langsamer"
        case .largeV3TurboQ5: return "Wie Turbo, ~⅓ der Größe, minimal schwächer"
        case .largeV3Turbo:   return "Beste Balance — schnell und sehr genau"
        case .largeV3:        return "Höchste Genauigkeit, deutlich langsamer"
        }
    }

    /// One model carries the "Empfohlen" badge in the UI. Currently large-v3-turbo:
    /// best speed/quality tradeoff for desktop dictation as of whisper.cpp v1.7.x.
    var isRecommended: Bool { self == .largeV3Turbo }

    var sourceURL: URL {
        URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/\(filename)")!
    }

    /// Resolves to ~/.blitzbot/models/<filename>.
    var localPath: URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home
            .appendingPathComponent(".blitzbot/models", isDirectory: true)
            .appendingPathComponent(filename)
    }

    /// Best-effort detection: if the configured path matches one of our known
    /// model filenames, return that model. Otherwise nil = custom/manual path.
    static func detect(fromPath path: String) -> WhisperModel? {
        let basename = (path as NSString).lastPathComponent
        return WhisperModel.allCases.first { $0.filename == basename }
    }
}

/// Streams a Whisper model from HuggingFace into `~/.blitzbot/models/`.
/// The active model can be changed via `setModel(_:)` between downloads.
///
/// Verification after download:
///   1. HTTP 200 + byte count ≥ 80 % of expected (rejects 404-HTML, truncation)
///   2. Magic bytes "GGUF" at offset 0 (whisper.cpp format sanity check)
///
/// We deliberately skip sha256 because ggerganov doesn't publish a stable hash
/// per model release, and HuggingFace's ETag header is not a sha256 either.
@MainActor
final class ModelDownloader: NSObject, ObservableObject {
    enum State: Equatable {
        case idle
        case checking
        case needsDownload(expectedBytes: Int64)
        case downloading(bytesDone: Int64, bytesTotal: Int64)
        case verifying
        case done
        case error(message: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var model: WhisperModel

    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var progressObservation: NSKeyValueObservation?

    init(model: WhisperModel = .largeV3Turbo) {
        self.model = model
        let dir = model.localPath.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        super.init()
    }

    var destinationPath: String { model.localPath.path }

    var modelExists: Bool {
        FileManager.default.fileExists(atPath: model.localPath.path)
    }

    /// Switches the active model. Resets state so the next `check()` reflects
    /// the new target.
    func setModel(_ model: WhisperModel) {
        guard model != self.model else { return }
        cancel()
        self.model = model
        state = .idle
    }

    /// Removes any other `ggml-*.bin` files in `~/.blitzbot/models/` that don't
    /// match the active model. Called after a successful switch to free disk.
    /// Returns the number of files removed.
    @discardableResult
    func purgeOtherModels() -> Int {
        let dir = model.localPath.deletingLastPathComponent()
        guard let files = try? FileManager.default.contentsOfDirectory(at: dir,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: []) else { return 0 }
        var removed = 0
        for url in files {
            let name = url.lastPathComponent
            guard name.hasPrefix("ggml-"), name.hasSuffix(".bin"),
                  name != model.filename else { continue }
            do {
                try FileManager.default.removeItem(at: url)
                removed += 1
                Log.write("ModelDownloader: purged old model \(name)")
            } catch {
                Log.write("ModelDownloader: purge failed for \(name): \(error)")
            }
        }
        return removed
    }

    /// Runs a HEAD request to confirm HuggingFace is reachable and the file
    /// exists. If the model is already on disk, short-circuits to `.done`.
    func check() async {
        if modelExists {
            state = .done
            return
        }
        state = .checking
        var req = URLRequest(url: model.sourceURL)
        req.httpMethod = "HEAD"
        req.timeoutInterval = 20
        do {
            let (_, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                state = .error(message: "Unbekannte Server-Antwort.")
                return
            }
            guard http.statusCode == 200 else {
                state = .error(message: "Server antwortete mit HTTP \(http.statusCode).")
                Log.write("ModelDownloader: HEAD got \(http.statusCode)")
                return
            }
            let bytes = http.expectedContentLength
            if bytes <= 0 {
                state = .needsDownload(expectedBytes: 0)
            } else {
                state = .needsDownload(expectedBytes: bytes)
            }
            Log.write("ModelDownloader: HEAD ok model=\(model.rawValue) bytes=\(bytes)")
        } catch {
            state = .error(message: "Server nicht erreichbar: \(error.localizedDescription)")
            Log.write("ModelDownloader: HEAD failed: \(error)")
        }
    }

    func startDownload() {
        // Cancel any stale session first.
        session?.invalidateAndCancel()

        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60 * 60  // 60 min — large-v3 is 3 GB
        configuration.waitsForConnectivity = true

        let session = URLSession(configuration: configuration)
        self.session = session

        state = .downloading(bytesDone: 0, bytesTotal: 0)

        let task = session.downloadTask(with: model.sourceURL) { [weak self] tempURL, response, error in
            let taskError = error
            let taskResponse = response
            let capturedTemp = tempURL
            Task { @MainActor [weak self] in
                await self?.finish(tempURL: capturedTemp, response: taskResponse, error: taskError)
            }
        }

        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let done = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor [weak self] in
                self?.state = .downloading(bytesDone: done, bytesTotal: max(total, 0))
            }
        }

        task.resume()
        self.task = task
        Log.write("ModelDownloader: download started model=\(model.rawValue)")
    }

    func cancel() {
        task?.cancel()
        task = nil
        progressObservation?.invalidate()
        progressObservation = nil
        session?.invalidateAndCancel()
        session = nil
        state = .idle
        Log.write("ModelDownloader: cancelled")
    }

    private func finish(tempURL: URL?, response: URLResponse?, error: Error?) async {
        progressObservation?.invalidate()
        progressObservation = nil

        if let error = error {
            let ns = error as NSError
            if ns.code == NSURLErrorCancelled { return }
            state = .error(message: "Download fehlgeschlagen: \(error.localizedDescription)")
            Log.write("ModelDownloader: error: \(error)")
            return
        }

        guard let tempURL else {
            state = .error(message: "Server lieferte keine Datei.")
            return
        }
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? -1
            state = .error(message: "Unerwartete Server-Antwort (HTTP \(code)).")
            try? FileManager.default.removeItem(at: tempURL)
            Log.write("ModelDownloader: bad response \(code)")
            return
        }

        state = .verifying
        do {
            let attrs = try FileManager.default.attributesOfItem(atPath: tempURL.path)
            let sizeNum = (attrs[.size] as? NSNumber)?.int64Value ?? 0
            // Accept anything ≥ 80 % of expected to tolerate compression / mirror diffs.
            let minExpected = Int64(Double(model.sizeMB) * 1_000_000 * 0.8)
            guard sizeNum >= minExpected else {
                state = .error(message: "Download scheint unvollständig (\(sizeNum) Bytes).")
                try? FileManager.default.removeItem(at: tempURL)
                Log.write("ModelDownloader: size too small=\(sizeNum) min=\(minExpected)")
                return
            }

            let handle = try FileHandle(forReadingFrom: tempURL)
            let magicData = try handle.read(upToCount: 4) ?? Data()
            try? handle.close()
            let magic = String(data: magicData, encoding: .ascii) ?? ""
            guard magic == "GGUF" else {
                state = .error(message: "Datei hat falsche Signatur (\(magic.isEmpty ? "leer" : magic)).")
                try? FileManager.default.removeItem(at: tempURL)
                Log.write("ModelDownloader: magic mismatch='\(magic)'")
                return
            }

            let destination = model.localPath
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            state = .done
            Log.write("ModelDownloader: done model=\(model.rawValue) size=\(sizeNum) path=\(destination.path)")
        } catch {
            state = .error(message: "Konnte Datei nicht speichern: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: tempURL)
            Log.write("ModelDownloader: finalize failed: \(error)")
        }
        session?.invalidateAndCancel()
        session = nil
        task = nil
    }
}
