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
            let resolvedLanguage = resolveLanguage(config: config,
                                                   whisperDetected: result.detectedLanguage,
                                                   transcript: raw)
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

    private func resolveLanguage(config: AppConfig,
                                 whisperDetected: String,
                                 transcript: String) -> String {
        switch config.outputLanguage {
        case .de: return "de"
        case .en: return "en"
        case .auto:
            // Trust content-based detection over whisper-cli's metadata on short utterances,
            // where whisper's auto-detect routinely labels clear English as "de".
            if let contentLang = Self.detectLanguageFromContent(transcript) {
                return contentLang
            }
            return whisperDetected.lowercased().hasPrefix("en") ? "en" : "de"
        }
    }

    // Simple stop-word ratio detector. Works on ~5 words+, robust enough to override
    // whisper-cli mis-detection on short clips.
    private static let englishStopwords: Set<String> = [
        "the","is","a","to","of","and","in","that","it","for","with","on","this","be","are",
        "from","as","at","by","an","or","not","have","has","was","were","will","can","would",
        "could","should","i","you","we","they","he","she","but","if","so","my","your","our",
        "what","how","when","where","why","which","who","do","does","did","just","about"
    ]
    private static let germanStopwords: Set<String> = [
        "der","die","das","und","ist","ich","ein","eine","nicht","mit","von","den","zu","auf",
        "dass","für","sich","als","im","wir","habe","werden","haben","war","wird","kann","ja",
        "also","mir","dich","mich","was","bei","noch","auch","dir","dem","du","sie","er","sein",
        "hat","hatte","würde","könnte","wenn","weil","aber","oder","aus","am","beim","ins","vom",
        "bitte","gerne","eventuell","einfach"
    ]

    private static func detectLanguageFromContent(_ text: String) -> String? {
        let lowered = text.lowercased()
        let tokens = lowered.split { $0.isWhitespace || $0.isPunctuation }.map(String.init)
        guard tokens.count >= 3 else { return nil }
        var en = 0
        var de = 0
        for token in tokens {
            if englishStopwords.contains(token) { en += 1 }
            if germanStopwords.contains(token) { de += 1 }
        }
        if en == 0 && de == 0 { return nil }
        if en >= de + 1 { return "en" }
        if de >= en + 1 { return "de" }
        return nil
    }
}
