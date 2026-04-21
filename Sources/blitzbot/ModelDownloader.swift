import Foundation

/// Streams the ggml-large-v3-turbo Whisper model from HuggingFace into
/// `~/.blitzbot/models/`. Single-shot per lifetime; a cancelled or failed
/// download wipes the partial file so the next attempt starts clean.
///
/// Verification after download:
///   1. HTTP 200 + byte count ≥ 100 MB (rejects 404-HTML, 0-byte, truncation)
///   2. Magic bytes "GGUF" at offset 0 (whisper.cpp format sanity check)
///
/// We deliberately skip sha256 because ggerganov doesn't publish a stable hash
/// per model release, and HuggingFace's ETag header is not a sha256 either.
/// Size + magic catches every realistic download failure mode.
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

    private let sourceURL = URL(string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo.bin")!
    private let destination: URL
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var progressObservation: NSKeyValueObservation?

    override init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let dir = home.appendingPathComponent(".blitzbot/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.destination = dir.appendingPathComponent("ggml-large-v3-turbo.bin")
        super.init()
    }

    var destinationPath: String { destination.path }

    var modelExists: Bool {
        FileManager.default.fileExists(atPath: destination.path)
    }

    /// Runs a HEAD request to confirm HuggingFace is reachable and the file
    /// exists. If the model is already on disk, short-circuits to `.done`.
    func check() async {
        if modelExists {
            state = .done
            return
        }
        state = .checking
        var req = URLRequest(url: sourceURL)
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
                // Fall through to download anyway — HEAD sometimes returns -1 (unknown).
                state = .needsDownload(expectedBytes: 0)
            } else {
                state = .needsDownload(expectedBytes: bytes)
            }
            Log.write("ModelDownloader: HEAD ok bytes=\(bytes)")
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
        configuration.timeoutIntervalForResource = 60 * 30  // 30 min total window
        configuration.waitsForConnectivity = true

        let session = URLSession(configuration: configuration)
        self.session = session

        state = .downloading(bytesDone: 0, bytesTotal: 0)

        let task = session.downloadTask(with: sourceURL) { [weak self] tempURL, response, error in
            let taskError = error
            let taskResponse = response
            let capturedTemp = tempURL
            Task { @MainActor [weak self] in
                await self?.finish(tempURL: capturedTemp, response: taskResponse, error: taskError)
            }
        }

        // KVO on Progress gives byte-level updates without needing a full delegate.
        progressObservation = task.progress.observe(\.fractionCompleted, options: [.new]) { [weak self] progress, _ in
            let done = progress.completedUnitCount
            let total = progress.totalUnitCount
            Task { @MainActor [weak self] in
                self?.state = .downloading(bytesDone: done, bytesTotal: max(total, 0))
            }
        }

        task.resume()
        self.task = task
        Log.write("ModelDownloader: download started")
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
            // Cancellation comes back as NSURLErrorCancelled — don't surface as a failure.
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
            guard sizeNum >= 100_000_000 else {
                state = .error(message: "Download scheint unvollständig (\(sizeNum) Bytes).")
                try? FileManager.default.removeItem(at: tempURL)
                Log.write("ModelDownloader: size too small=\(sizeNum)")
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

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: tempURL, to: destination)
            state = .done
            Log.write("ModelDownloader: done size=\(sizeNum) path=\(destination.path)")
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
