import Foundation
import Combine
import AppKit

@MainActor
final class ModeProcessor: ObservableObject {
    enum Status: Equatable {
        case bereit
        case aufnahme
        case transkribiert
        case formuliert
        case fertig
        case fehler(String)
        /// Recoverable LLM failure. HUD stays open and offers a profile-switch retry.
        /// The real recovery state (transcript, prompt, timer) lives in `recoveryContext`.
        case recovery(String)

        var label: String {
            switch self {
            case .bereit:         return "Bereit"
            case .aufnahme:       return "Aufnahme…"
            case .transkribiert:  return "Transkribiert…"
            case .formuliert:     return "Formuliert…"
            case .fertig:         return "Fertig"
            case .fehler(let m):  return "Fehler: \(m)"
            case .recovery(let m): return "Verbindungsfehler: \(m)"
            }
        }
    }

    /// Snapshot of everything needed to retry a failed LLM call against a
    /// different connection profile — without re-transcribing.
    ///
    /// Lives only in memory + mirrored to the system pasteboard (safety net);
    /// never written to disk, per privacy rules. 30 s after entering recovery
    /// the state is discarded (transcript stays in the pasteboard).
    struct RecoveryContext: Equatable {
        let transcript: String
        let mode: Mode
        let systemPrompt: String
        let language: String
        let autoReturn: Bool
        /// Profile that just failed. UI disables this entry so the user can't
        /// pick the same broken endpoint again.
        let failedProfileID: UUID?
        var secondsLeft: Int
    }

    @Published var status: Status = .bereit {
        didSet {
            // Clear processing UI hints whenever we leave a processing phase.
            switch status {
            case .transkribiert, .formuliert, .recovery: break
            default:
                processingStartedAt = nil
                activeProviderLabel = nil
            }
            // Live partial belongs to the recording phase only.
            if status != .aufnahme {
                livePartial = .empty
                Task { await liveTranscriber.stop() }
            }
        }
    }
    @Published var activeMode: Mode?

    /// Active recovery state. `nil` whenever we're not in a recovery flow.
    @Published var recoveryContext: RecoveryContext?

    /// Clears a stuck `.fehler` back to `.bereit`. No-op if another status is active.
    func clearErrorIfAny() {
        if case .fehler = status { status = .bereit }
    }

    @Published var elapsed: TimeInterval = 0
    @Published var detectedLanguage: String?
    /// Per-recording toggle: when on, a Return is simulated after the paste so chat-apps submit.
    /// Non-persistent — resets to false at the start of each recording.
    @Published var autoExecute: Bool = false
    /// Seconds remaining until auto-stop fires (nil = not counting down / voice active).
    @Published var autoStopSecondsLeft: Int? = nil
    /// True when audio level has been below the silence threshold since last voice activity.
    @Published var isInSilence: Bool = false
    /// True after 5 seconds of continuous silence — drives the "Stille erkannt" banner.
    @Published var showSilenceBanner: Bool = false
    /// True when recording is paused (engine paused, file kept open).
    @Published var isPaused: Bool = false
    /// Auto-stop timeout configured for the current recording (for HUD progress display).
    @Published var autoStopTimeoutForDisplay: TimeInterval = 45
    /// True when audio level is above the voice threshold — drives "Stimme erkannt" badge.
    @Published var hasVoiceActivity: Bool = false
    /// Timestamp when the current post-recording phase (transcribing / formulating)
    /// started. The HUD reads this and displays elapsed seconds so the user knows
    /// the wait isn't a hang. Nil outside processing phases.
    @Published var processingStartedAt: Date?
    /// Provider name shown in the HUD during the LLM step (e.g. "Anthropic", "Ollama").
    /// Set when entering `.formuliert`, cleared on terminal status.
    @Published var activeProviderLabel: String?
    /// Live partial transcript snapshot from Apple's macOS-26 SpeechTranscriber.
    /// Empty when the live engine is disabled, unavailable, or the recording
    /// hasn't produced any text yet. Cleared on stop so it doesn't bleed into
    /// the next session.
    @Published var livePartial: LivePartial = .empty

    let recorder = AudioRecorder()
    /// nonisolated so the audio-thread tap closure can call `feed` without a
    /// MainActor hop (which crashes via `dispatch_assert_queue_fail`).
    nonisolated let liveTranscriber = LiveTranscriberManager()
    private var isRecording = false
    private var isProcessing = false      // reentrancy guard for stopAndProcess
    private var startedAt: Date?
    private var tickTimer: Timer?
    private var inactivityTimer: Timer?
    private var inactivityTimerDeadline: Date?
    private var silenceBannerTimer: Timer?
    private var recoveryTimer: Timer?
    private var levelCancellable: AnyCancellable?
    private var voiceActivityCancellable: AnyCancellable?
    private static let silenceThreshold: Float = 0.03
    private static let silenceBannerDelay: TimeInterval = 5
    /// How long the user has to pick a new profile before the recovery state
    /// is discarded (transcript remains on the pasteboard as a safety net).
    static let recoveryTimeoutSeconds: TimeInterval = 30

    func toggle(mode: Mode, config: AppConfig) {
        // Non-voice modes (e.g. officeMode) must not drive the recording pipeline;
        // they have their own window. Defensive guard — callers already filter.
        guard mode.isVoiceMode else {
            Log.write("ModeProcessor.toggle ignored: \(mode.rawValue) is not a voice mode")
            return
        }
        if isRecording {
            if activeMode == mode {
                Task { await stopAndProcess(config: config) }
            } else {
                let previous = activeMode
                activeMode = mode
                Log.write("Mode switched while recording: \(previous?.rawValue ?? "nil") → \(mode.rawValue)")
            }
        } else {
            startRecording(mode: mode, config: config)
        }
    }

    func cancel() {
        tearDownInactivityTimer()
        tickTimer?.invalidate()
        tickTimer = nil
        startedAt = nil
        if let url = recorder.stop() {
            try? FileManager.default.removeItem(at: url)
            Log.write("REC cancelled — wav deleted: \(url.lastPathComponent)")
        }
        isRecording = false
        isPaused = false
        autoExecute = false
        activeMode = nil
        status = .bereit   // didSet stops the live transcriber and clears livePartial
    }

    func pauseRecording(config: AppConfig) {
        guard isRecording, !isPaused else { return }
        tearDownInactivityTimer()
        recorder.pause()
        isPaused = true
        Log.write("REC paused")
    }

    func resumeRecording(config: AppConfig) {
        guard isRecording, isPaused else { return }
        do {
            try recorder.resume()
            isPaused = false
            startInactivityTimer(config: config)
            Log.write("REC resumed")
        } catch {
            Log.write("REC resume FAILED: \(error)")
            status = .fehler(error.localizedDescription)
        }
    }

    private func startRecording(mode: Mode, config: AppConfig) {
        // Starting a new recording supersedes any pending recovery state.
        // The previous transcript is safe on the pasteboard (mirrored when
        // recovery was entered), so we just drop the state and move on.
        if recoveryContext != nil {
            Log.write("Recovery: abandoned — new recording started (transcript still in clipboard)")
            invalidateRecoveryTimer()
            recoveryContext = nil
        }
        do {
            let url = try recorder.start(preferredMicUID: config.preferredMicUID)
            activeMode = mode
            detectedLanguage = nil
            autoExecute = false
            isPaused = false
            isRecording = true
            autoStopTimeoutForDisplay = config.autoStopTimeout
            status = .aufnahme
            startLiveTranscriptionIfEnabled(config: config)
            let now = Date()
            startedAt = now
            elapsed = 0
            tickTimer?.invalidate()
            tickTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self else { return }
                    self.elapsed = Date().timeIntervalSince(now)
                    if let deadline = self.inactivityTimerDeadline {
                        let secs = Int(ceil(deadline.timeIntervalSinceNow))
                        self.autoStopSecondsLeft = secs > 0 ? secs : nil
                    }
                }
            }
            Log.write("REC start mode=\(mode) file=\(url.lastPathComponent)")
            startVoiceActivityMonitor()
            startInactivityTimer(config: config)
        } catch {
            Log.write("REC start FAILED: \(error)")
            status = .fehler(error.localizedDescription)
        }
    }

    private func startVoiceActivityMonitor() {
        voiceActivityCancellable = recorder.$level
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.isRecording, !self.isPaused else {
                    self?.hasVoiceActivity = false
                    return
                }
                self.hasVoiceActivity = level > Self.silenceThreshold
            }
    }

    private func startInactivityTimer(config: AppConfig) {
        guard config.autoStopEnabled else { return }
        inactivityTimer?.invalidate()
        levelCancellable = recorder.$level
            .receive(on: DispatchQueue.main)
            .sink { [weak self] level in
                guard let self, self.isRecording else { return }
                if level > Self.silenceThreshold {
                    // Voice detected — reset everything
                    self.isInSilence = false
                    self.showSilenceBanner = false
                    self.silenceBannerTimer?.invalidate()
                    self.silenceBannerTimer = nil
                    self.resetInactivityCountdown(config: config)
                } else {
                    // Silence — schedule banner after 5s delay if not already pending
                    if !self.isInSilence {
                        self.isInSilence = true
                        self.silenceBannerTimer?.invalidate()
                        self.silenceBannerTimer = Timer.scheduledTimer(
                            withTimeInterval: Self.silenceBannerDelay,
                            repeats: false
                        ) { [weak self] _ in
                            DispatchQueue.main.async { self?.showSilenceBanner = true }
                        }
                    }
                }
            }
        resetInactivityCountdown(config: config)
    }

    private func resetInactivityCountdown(config: AppConfig) {
        inactivityTimer?.invalidate()
        let deadline = Date().addingTimeInterval(config.autoStopTimeout)
        inactivityTimerDeadline = deadline
        inactivityTimer = Timer.scheduledTimer(
            withTimeInterval: config.autoStopTimeout,
            repeats: false
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.isRecording else { return }
                Log.write("Auto-Stop: \(Int(config.autoStopTimeout))s Inaktivität — verarbeite Aufnahme")
                await self.stopAndProcess(config: config)
            }
        }
    }

    private func tearDownInactivityTimer() {
        inactivityTimer?.invalidate()
        inactivityTimer = nil
        inactivityTimerDeadline = nil
        silenceBannerTimer?.invalidate()
        silenceBannerTimer = nil
        levelCancellable = nil
        voiceActivityCancellable = nil
        isInSilence = false
        showSilenceBanner = false
        hasVoiceActivity = false
        autoStopSecondsLeft = nil
    }

    private func stopAndProcess(config: AppConfig) async {
        // Reentrancy guard: auto-stop timer and manual hotkey can both dispatch
        // stopAndProcess within the same run-loop cycle. The second call must not
        // proceed — recorder.stop() would return nil and the recording would be lost.
        guard !isProcessing else {
            Log.write("stopAndProcess: duplicate call ignored (already processing)")
            return
        }
        isProcessing = true
        defer { isProcessing = false }

        tearDownInactivityTimer()
        tickTimer?.invalidate()
        tickTimer = nil
        startedAt = nil
        isPaused = false
        // Reset isRecording BEFORE recorder.stop() so that even if the guard below
        // fails (recorder already stopped), the state machine is left clean.
        isRecording = false

        guard let url = recorder.stop(), let mode = activeMode else {
            Log.write("stopAndProcess: recorder.stop() returned nil — recording was already stopped or never started")
            status = .fehler("Aufnahme verloren")
            activeMode = nil
            return
        }
        processingStartedAt = Date()
        activeProviderLabel = nil
        status = .transkribiert

        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int) ?? 0
        Log.write("REC stop mode=\(mode) wav=\(url.path) bytes=\(size)")

        let transcriber = WhisperTranscriber(binaryPath: config.whisperBinary,
                                             modelPath: config.whisperModel,
                                             language: config.outputLanguage.whisperLanguageFlag,
                                             vocabularyPrompt: config.vocabularyPrompt)
        let raw: String
        let resolvedLanguage: String
        do {
            let result = try transcriber.transcribe(audioURL: url)
            raw = result.text
            resolvedLanguage = resolveLanguage(config: config,
                                               whisperDetected: result.detectedLanguage,
                                               transcript: raw)
            detectedLanguage = resolvedLanguage
            Log.write("TRANSCRIPT lang=\(resolvedLanguage) (whisper=\(result.detectedLanguage)): <\(raw.count) chars>")
        } catch {
            Log.write("ERROR Whisper: \(error)")
            status = .fehler(error.localizedDescription)
            activeMode = nil
            return
        }
        guard !raw.isEmpty else {
            status = .fehler("Leere Transkription")
            activeMode = nil
            return
        }

        let prompt = config.prompt(for: mode, language: resolvedLanguage)
        await processTranscript(raw: raw,
                                mode: mode,
                                language: resolvedLanguage,
                                prompt: prompt,
                                autoReturn: autoExecute,
                                config: config,
                                profileOverride: nil)
    }

    /// Runs the LLM step + paste. Factored out so the recovery retry path can
    /// re-enter it with a different profile without re-transcribing.
    ///
    /// On a recoverable LLM failure, seeds `recoveryContext` and switches status
    /// to `.recovery(message)` instead of bubbling up a dead-end error.
    private func processTranscript(raw: String,
                                   mode: Mode,
                                   language: String,
                                   prompt: String,
                                   autoReturn: Bool,
                                   config: AppConfig,
                                   profileOverride: ConnectionProfile?) async {
        var output = raw
        if !prompt.isEmpty {
            activeProviderLabel = profileOverride?.name
                ?? config.profileStore.activeProfile?.name
                ?? config.llmProvider.displayName
            processingStartedAt = Date()
            status = .formuliert
            do {
                if let override = profileOverride {
                    output = try await LLMRouter.rewrite(text: raw,
                                                         systemPrompt: prompt,
                                                         config: config,
                                                         profileOverride: override,
                                                         mode: mode)
                } else {
                    output = try await LLMRouter.rewrite(text: raw,
                                                         systemPrompt: prompt,
                                                         config: config,
                                                         mode: mode)
                }
            } catch {
                let providerLabel = profileOverride?.name
                    ?? config.profileStore.activeProfile?.name
                    ?? config.llmProvider.displayName
                let llmErr = LLMError.classify(error, provider: providerLabel)
                Log.write("ERROR LLM (\(providerLabel)): \(llmErr.errorDescription ?? "unknown")")
                if llmErr.isRecoverable {
                    let ctx = RecoveryContext(
                        transcript: raw,
                        mode: mode,
                        systemPrompt: prompt,
                        language: language,
                        autoReturn: autoReturn,
                        failedProfileID: profileOverride?.id ?? config.profileStore.activeProfileID,
                        secondsLeft: Int(Self.recoveryTimeoutSeconds)
                    )
                    enterRecovery(context: ctx,
                                  errorMessage: llmErr.errorDescription ?? "Verbindungsfehler")
                    return
                }
                status = .fehler(llmErr.errorDescription ?? "Fehler")
                activeMode = nil
                return
            }
        }
        let outputTrimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !outputTrimmed.isEmpty else {
            Log.write("PASTE skipped: empty output after processing")
            status = .fehler("Leeres Ergebnis")
            activeMode = nil
            return
        }
        Log.write("PASTE len=\(output.count) autoReturn=\(autoReturn)")
        Paster.pasteText(output, autoReturn: autoReturn)
        status = .fertig
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        if case .fertig = status {
            status = .bereit
            activeMode = nil
        }
    }

    // MARK: - Recovery (inline HUD)

    /// Seeds recovery state and starts the 30 s countdown. Mirrors the transcript
    /// to the system pasteboard *before* anything else so a crash or user abandon
    /// never loses the recording.
    private func enterRecovery(context: RecoveryContext, errorMessage: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(context.transcript, forType: .string)
        Log.write("Recovery: entered (\(errorMessage)) — transcript mirrored to clipboard (\(context.transcript.count) chars)")

        recoveryContext = context
        status = .recovery(errorMessage)

        invalidateRecoveryTimer()
        recoveryTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.tickRecoveryTimer()
            }
        }
    }

    private func tickRecoveryTimer() {
        guard var ctx = recoveryContext else {
            invalidateRecoveryTimer()
            return
        }
        ctx.secondsLeft -= 1
        if ctx.secondsLeft <= 0 {
            Log.write("Recovery: 30s timeout — transcript stays in clipboard")
            invalidateRecoveryTimer()
            recoveryContext = nil
            status = .bereit
            activeMode = nil
        } else {
            recoveryContext = ctx
        }
    }

    private func invalidateRecoveryTimer() {
        recoveryTimer?.invalidate()
        recoveryTimer = nil
    }

    /// User dismissed the recovery panel. Transcript remains on the pasteboard.
    func cancelRecovery() {
        guard recoveryContext != nil else { return }
        Log.write("Recovery: user cancelled — transcript stays in clipboard")
        invalidateRecoveryTimer()
        recoveryContext = nil
        status = .bereit
        activeMode = nil
    }

    /// User picked an alternative profile. Re-runs the LLM step with the same
    /// transcript/prompt against `profile`. If this one also fails recoverably,
    /// we re-enter recovery with the new failed profile marked.
    func retryWithProfile(_ profile: ConnectionProfile, config: AppConfig) {
        guard let ctx = recoveryContext else { return }
        guard profile.id != ctx.failedProfileID else {
            Log.write("Recovery: retry ignored — same profile as failed")
            return
        }
        invalidateRecoveryTimer()
        recoveryContext = nil
        let raw = ctx.transcript
        let mode = ctx.mode
        let language = ctx.language
        let prompt = ctx.systemPrompt
        let autoReturn = ctx.autoReturn
        Log.write("Recovery: retry with profile \"\(profile.name)\" (\(profile.provider.rawValue))")
        Task { [weak self] in
            await self?.processTranscript(raw: raw,
                                          mode: mode,
                                          language: language,
                                          prompt: prompt,
                                          autoReturn: autoReturn,
                                          config: config,
                                          profileOverride: profile)
        }
    }

    // MARK: - Live transcription

    /// Spawns Apple's `SpeechTranscriber` and wires it to the audio recorder's
    /// buffer tap. No-op when disabled in Settings or when the runtime isn't
    /// macOS 26 + 16-core ANE — recording continues unaffected.
    private func startLiveTranscriptionIfEnabled(config: AppConfig) {
        guard config.liveTranscriptionEnabled, liveTranscriber.isHardwareCapable else { return }
        let locale = liveLocale(for: config)
        Task { [weak self] in
            guard let self else { return }
            await self.liveTranscriber.start(locale: locale) { [weak self] partial in
                self?.livePartial = partial
            }
        }
        recorder.bufferTap = { [weak self] buffer, time in
            self?.liveTranscriber.feed(buffer, time: time)
        }
    }

    /// Apple's `SpeechTranscriber` is locale-bound (no auto-detect). We follow
    /// the user's output-language preference; on Auto we default to German
    /// since that's the primary dictation language in practice. Whisper's
    /// auto-detect on the final pass still routes correctly either way.
    private func liveLocale(for config: AppConfig) -> String {
        switch config.outputLanguage {
        case .en: return "en-US"
        case .de, .auto: return "de-DE"
        }
    }

    // MARK: - Orphaned recording recovery

    /// Patches RIFF + data chunk sizes in a WAV whose header was never finalized
    /// because the writer process was killed mid-recording. AVAudioFile only writes
    /// the chunk-size fields on close, so an orphaned file has audio bytes but a
    /// 0-byte data chunk — Whisper then reads 0 frames and returns empty.
    /// Returns true iff the header was modified.
    private static func repairWAVHeader(at url: URL) -> Bool {
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let sizeInt = attrs[.size] as? Int,
              let totalSize = UInt32(exactly: sizeInt),
              totalSize > 44 else { return false }

        guard let handle = try? FileHandle(forUpdating: url) else { return false }
        defer { try? handle.close() }

        do {
            try handle.seek(toOffset: 0)
            guard let head = try handle.read(upToCount: 12), head.count == 12,
                  head.prefix(4) == Data("RIFF".utf8),
                  head.subdata(in: 8..<12) == Data("WAVE".utf8) else { return false }
        } catch { return false }

        // Walk chunks until we find "data".
        var pos: UInt32 = 12
        var dataSizeFieldOffset: UInt32? = nil
        while pos &+ 8 <= totalSize {
            do {
                try handle.seek(toOffset: UInt64(pos))
                guard let header = try handle.read(upToCount: 8), header.count == 8 else { return false }
                let id = header.prefix(4)
                let storedSize = header.subdata(in: 4..<8).withUnsafeBytes { $0.load(as: UInt32.self) }
                if id == Data("data".utf8) {
                    dataSizeFieldOffset = pos &+ 4
                    break
                }
                if storedSize == 0 { return false }   // corrupt non-data chunk; bail
                let padded = storedSize &+ (storedSize & 1)
                pos = pos &+ padded &+ 8
            } catch { return false }
        }
        guard let dataSizeOff = dataSizeFieldOffset else { return false }

        let expectedRiff = totalSize - 8
        let expectedData = totalSize - dataSizeOff - 4

        // Read current header values to skip the write if already correct.
        let currentRiff: UInt32
        let currentData: UInt32
        do {
            try handle.seek(toOffset: 4)
            currentRiff = (try handle.read(upToCount: 4))?.withUnsafeBytes { $0.load(as: UInt32.self) } ?? 0
            try handle.seek(toOffset: UInt64(dataSizeOff))
            currentData = (try handle.read(upToCount: 4))?.withUnsafeBytes { $0.load(as: UInt32.self) } ?? 0
        } catch { return false }

        if currentRiff == expectedRiff && currentData == expectedData { return false }

        var riffLE = expectedRiff.littleEndian
        var dataLE = expectedData.littleEndian
        do {
            try handle.seek(toOffset: 4)
            try handle.write(contentsOf: Data(bytes: &riffLE, count: 4))
            try handle.seek(toOffset: UInt64(dataSizeOff))
            try handle.write(contentsOf: Data(bytes: &dataLE, count: 4))
            try handle.synchronize()
        } catch { return false }

        return true
    }

    /// Called at launch to recover any WAV files left behind by a previous run that
    /// was killed or crashed during an active recording. Transcribes the most recent
    /// orphaned file (if any), copies the result to the clipboard, and sets a visible
    /// error status so the user knows something was recovered.
    func recoverOrphanedRecordings(config: AppConfig) {
        guard !config.whisperBinary.isEmpty, !config.whisperModel.isEmpty else { return }
        let tmp = FileManager.default.temporaryDirectory
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: tmp, includingPropertiesForKeys: [.creationDateKey], options: []) else { return }
        let cutoff = Date().addingTimeInterval(-6 * 3600)  // ignore files older than 6 h
        let orphans = files
            .filter { $0.lastPathComponent.hasPrefix("blitzbot-") && $0.pathExtension == "wav" }
            .filter { (try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate).flatMap { $0 > cutoff } ?? false }
            .sorted { a, b in
                let da = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                let db = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast
                return da > db
            }
        guard let best = orphans.first else { return }
        let size = (try? FileManager.default.attributesOfItem(atPath: best.path)[.size] as? Int) ?? 0
        guard size > 10_000 else {   // skip nearly-empty files (false starts)
            orphans.forEach { try? FileManager.default.removeItem(at: $0) }
            return
        }
        Log.write("Recovery: found orphaned recording \(best.lastPathComponent) (\(size) bytes) — transcribing")
        if Self.repairWAVHeader(at: best) {
            Log.write("Recovery: WAV header was unfinalized — patched RIFF + data sizes")
        }
        Task {
            let transcriber = WhisperTranscriber(binaryPath: config.whisperBinary,
                                                 modelPath: config.whisperModel,
                                                 language: config.outputLanguage.whisperLanguageFlag,
                                                 vocabularyPrompt: config.vocabularyPrompt)
            do {
                let result = try transcriber.transcribe(audioURL: best)
                let text = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
                orphans.forEach { try? FileManager.default.removeItem(at: $0) }
                guard !text.isEmpty else {
                    Log.write("Recovery: transcript empty — nothing to restore")
                    return
                }
                await MainActor.run {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                    Log.write("Recovery: \(text.count) chars copied to clipboard")
                    self.status = .fehler("Aufnahme wiederhergestellt — in Zwischenablage")
                    Task {
                        try? await Task.sleep(nanoseconds: 5_000_000_000)
                        if case .fehler = self.status { self.status = .bereit }
                    }
                }
            } catch {
                Log.write("Recovery: transcription failed — \(error)")
                orphans.forEach { try? FileManager.default.removeItem(at: $0) }
            }
        }
    }

    // MARK: - Language detection

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
