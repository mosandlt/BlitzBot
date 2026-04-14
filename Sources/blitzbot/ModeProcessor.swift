import Foundation

@MainActor
final class ModeProcessor: ObservableObject {
    enum Status: Equatable {
        case bereit
        case aufnahme
        case transkribiert
        case formuliert
        case fertig
        case fehler(String)

        var label: String {
            switch self {
            case .bereit:         return "Bereit"
            case .aufnahme:       return "Aufnahme…"
            case .transkribiert:  return "Transkribiert…"
            case .formuliert:     return "Formuliert…"
            case .fertig:         return "Fertig"
            case .fehler(let m):  return "Fehler: \(m)"
            }
        }
    }

    @Published var status: Status = .bereit
    @Published var activeMode: Mode?
    @Published var elapsed: TimeInterval = 0
    @Published var detectedLanguage: String?

    let recorder = AudioRecorder()
    private var isRecording = false
    private var startedAt: Date?
    private var tickTimer: Timer?

    func toggle(mode: Mode, config: AppConfig) {
        if isRecording {
            if activeMode == mode {
                Task { await stopAndProcess(config: config) }
            } else {
                let previous = activeMode
                activeMode = mode
                Log.write("Mode switched while recording: \(previous?.rawValue ?? "nil") → \(mode.rawValue)")
            }
        } else {
            startRecording(mode: mode)
        }
    }

    private func startRecording(mode: Mode) {
        do {
            let url = try recorder.start()
            activeMode = mode
            detectedLanguage = nil
            isRecording = true
            status = .aufnahme
            let now = Date()
            startedAt = now
            elapsed = 0
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.elapsed = Date().timeIntervalSince(now) }
            }
            Log.write("REC start mode=\(mode) file=\(url.lastPathComponent)")
        } catch {
            Log.write("REC start FAILED: \(error)")
            status = .fehler(error.localizedDescription)
        }
    }

    private func stopAndProcess(config: AppConfig) async {
        tickTimer?.invalidate()
        tickTimer = nil
        startedAt = nil
        guard let url = recorder.stop(), let mode = activeMode else {
            status = .fehler("Keine Aufnahme")
            return
        }
        isRecording = false
        status = .transkribiert

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        Log.write("REC stop mode=\(mode) wav=\(url.path) bytes=\(size)")

        let transcriber = WhisperTranscriber(binaryPath: config.whisperBinary,
                                             modelPath: config.whisperModel,
                                             language: config.outputLanguage.whisperLanguageFlag,
                                             vocabularyPrompt: config.vocabularyPrompt)
        do {
            let result = try transcriber.transcribe(audioURL: url)
            let raw = result.text
            let resolvedLanguage = resolveLanguage(config: config, detected: result.detectedLanguage)
            detectedLanguage = resolvedLanguage
            Log.write("TRANSCRIPT lang=\(resolvedLanguage) (whisper=\(result.detectedLanguage)): \"\(raw)\"")
            guard !raw.isEmpty else {
                status = .fehler("Leere Transkription")
                return
            }
            var output = raw
            let prompt = config.prompt(for: mode, language: resolvedLanguage)
            if !prompt.isEmpty {
                status = .formuliert
                guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
                    status = .fehler("Kein Anthropic API Key")
                    return
                }
                let client = AnthropicClient(apiKey: apiKey, model: config.model)
                output = try await client.rewrite(text: raw, systemPrompt: prompt)
            }
            Log.write("PASTE len=\(output.count)")
            Paster.pasteText(output)
            status = .fertig
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            if case .fertig = status {
                status = .bereit
                activeMode = nil
            }
        } catch {
            Log.write("ERROR: \(error)")
            status = .fehler(error.localizedDescription)
            activeMode = nil
        }
    }

    private func resolveLanguage(config: AppConfig, detected: String) -> String {
        switch config.outputLanguage {
        case .auto:
            let normalized = detected.lowercased()
            if normalized.hasPrefix("en") { return "en" }
            return "de"
        case .de:
            return "de"
        case .en:
            return "en"
        }
    }
}
