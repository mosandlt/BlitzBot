import AVFoundation
import CoreMedia
import Foundation
#if canImport(Speech)
import Speech
#endif

/// Snapshot of what the live transcriber knows right now.
/// `confirmed` segments are stable (Apple guarantees they don't change once delivered).
/// `volatile` is the in-flight tail that may rewrite as more audio arrives.
struct LivePartial: Equatable {
    var confirmed: String
    var volatile: String

    var combined: String {
        if volatile.isEmpty { return confirmed }
        if confirmed.isEmpty { return volatile }
        return confirmed + " " + volatile
    }

    static let empty = LivePartial(confirmed: "", volatile: "")
}

/// Drives Apple's macOS 26 `SpeechTranscriber` for live partial-text display
/// while a recording is in progress. The final transcript still comes from the
/// existing whisper-cli batch pass — this is purely visual feedback so the user
/// sees their words appear as they speak instead of staring at a static HUD.
///
/// **Not** `@MainActor` — `feed(_:time:)` is called from the AVAudioEngine
/// tap thread (`RealtimeMessenger.mServiceQueue`), and `MainActor.assumeIsolated`
/// from there crashes with `dispatch_assert_queue_fail`. Internal state is
/// protected by an explicit lock instead.
final class LiveTranscriberManager: @unchecked Sendable {
    private let lock = NSLock()
    // Stored as soon as the AppleLiveTranscriber is created so that feed() on the
    // audio-render thread can route buffers immediately. AppleLiveTranscriber.feed()
    // itself guards on inputContinuation != nil, so early calls (before the analyzer
    // is ready) are safely dropped without touching the audio engine.
    private var inner: AnyObject?
    private var _isRunning = false

    var isRunning: Bool {
        lock.lock(); defer { lock.unlock() }
        return _isRunning
    }

    var isHardwareCapable: Bool {
        if #available(macOS 26.0, *) {
            return AppleLiveTranscriber.isHardwareCapable
        }
        return false
    }

    func start(locale: String, onPartial: @escaping @MainActor (LivePartial) -> Void) async {
        lock.lock()
        let already = _isRunning
        lock.unlock()
        guard !already else { return }
        if #available(macOS 26.0, *) {
            let transcriber = AppleLiveTranscriber()
            // Set immediately so the audio-render tap can call feed() from the first
            // buffer onwards. AppleLiveTranscriber.feed() gates on inputContinuation,
            // so pre-setup calls are no-ops, not crashes.
            // stop() sets isStopped=true on the transcriber so any concurrent start()
            // await returns early and the analyzer is cleaned up.
            lock.lock()
            inner = transcriber
            lock.unlock()
            do {
                try await transcriber.start(locale: locale, onPartial: onPartial)
                lock.lock()
                _isRunning = true
                lock.unlock()
            } catch {
                Log.write("LiveTranscriber: start failed — \(error)")
                lock.lock()
                if inner === transcriber { inner = nil }
                lock.unlock()
            }
        }
    }

    /// Called from the AVAudioEngine tap thread (audio render queue).
    /// Synchronous + lock-only — no actor hops, so the tap buffer is consumed
    /// before AVAudioEngine can recycle its underlying memory.
    func feed(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        lock.lock()
        let t = inner
        lock.unlock()
        if #available(macOS 26.0, *), let app = t as? AppleLiveTranscriber {
            app.feed(buffer, time: time)
        }
    }

    func stop() async {
        lock.lock()
        let t = inner
        inner = nil
        _isRunning = false
        lock.unlock()
        guard let t else { return }
        if #available(macOS 26.0, *), let app = t as? AppleLiveTranscriber {
            await app.stop()
        }
    }
}

#if canImport(Speech)
@available(macOS 26.0, *)
final class AppleLiveTranscriber: @unchecked Sendable {
    // Mutable state — accessed from both the audio tap thread (feed) and
    // MainActor (start/stop). Serialized via the lock below.
    private var analyzer: SpeechAnalyzer?
    private var transcriber: SpeechTranscriber?
    private var inputContinuation: AsyncStream<AnalyzerInput>.Continuation?
    private var converter: AVAudioConverter?
    private var targetFormat: AVAudioFormat?
    private var resultsTask: Task<Void, Never>?

    private var confirmedText: String = ""
    private var bufferCount: Int = 0
    private var onPartialCallback: (@MainActor (LivePartial) -> Void)?
    // Set by stop() so that a concurrent start() can detect it was superseded.
    private var isStopped = false

    private let lock = NSLock()

    static var isHardwareCapable: Bool {
        SpeechTranscriber.isAvailable
    }

    @MainActor
    func start(locale: String, onPartial: @escaping @MainActor (LivePartial) -> Void) async throws {
        let trans = SpeechTranscriber(
            locale: Locale(identifier: locale),
            transcriptionOptions: [],
            reportingOptions: [.volatileResults, .fastResults],
            attributeOptions: []
        )

        // Await asset installation before starting the analyzer — firing it
        // detached while the analyzer starts causes a race where the analyzer
        // runs without the models being ready yet.
        if let req = try? await AssetInventory.assetInstallationRequest(supporting: [trans]) {
            do {
                try await req.downloadAndInstall()
                Log.write("LiveTranscriber: asset install completed for \(locale)")
            } catch {
                Log.write("LiveTranscriber: asset install failed for \(locale): \(error)")
            }
        }

        // If stop() was called while we were awaiting the asset install, bail.
        lock.lock()
        let alreadyStopped = isStopped
        lock.unlock()
        if alreadyStopped { return }

        guard let format = await SpeechAnalyzer.bestAvailableAudioFormat(compatibleWith: [trans]) else {
            throw NSError(domain: "AppleLiveTranscriber", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No compatible audio format"])
        }

        // Check again — another await above.
        lock.lock()
        let stoppedAfterFormat = isStopped
        lock.unlock()
        if stoppedAfterFormat { return }

        let (stream, cont) = AsyncStream<AnalyzerInput>.makeStream(bufferingPolicy: .bufferingNewest(128))

        lock.lock()
        targetFormat = format
        inputContinuation = cont
        confirmedText = ""
        bufferCount = 0
        onPartialCallback = onPartial
        lock.unlock()

        let analyzer = SpeechAnalyzer(modules: [trans],
                                      options: SpeechAnalyzer.Options(priority: .userInitiated,
                                                                      modelRetention: .lingering))

        // Start the result drain BEFORE starting the analyzer so we never miss
        // the first segment.
        let task = Task { [weak self, trans] in
            Log.write("LiveTranscriber: result drain task started")
            guard let self else { return }
            do {
                for try await result in trans.results {
                    if Task.isCancelled {
                        Log.write("LiveTranscriber: result drain cancelled")
                        return
                    }
                    let text = String(result.text.characters)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    self.lock.lock()
                    let snap: LivePartial
                    if result.isFinal {
                        if !text.isEmpty {
                            self.confirmedText = self.appendSegment(self.confirmedText, text)
                        }
                        snap = LivePartial(confirmed: self.confirmedText, volatile: "")
                    } else {
                        snap = LivePartial(confirmed: self.confirmedText, volatile: text)
                    }
                    let cb = self.onPartialCallback
                    self.lock.unlock()
                    Log.write("LiveTranscriber: result final=\(result.isFinal) text=\"\(text.prefix(40))\" totalConfirmed=\(snap.confirmed.count)")
                    if let cb {
                        await MainActor.run { cb(snap) }
                    }
                }
            } catch {
                Log.write("LiveTranscriber: results stream error — \(error)")
            }
            Log.write("LiveTranscriber: result drain task ended")
        }

        try await analyzer.start(inputSequence: stream)

        // If stop() was called while analyzer was starting, clean up the analyzer
        // we just started so it doesn't become a dangling resource.
        lock.lock()
        let stoppedDuringStart = isStopped
        lock.unlock()
        if stoppedDuringStart {
            task.cancel()
            cont.finish()
            try? await analyzer.finalizeAndFinishThroughEndOfInput()
            Log.write("LiveTranscriber: stopped during start(), cleaned up")
            return
        }

        self.analyzer = analyzer
        self.transcriber = trans
        self.resultsTask = task

        Log.write("LiveTranscriber: started locale=\(locale) format=\(format)")
    }

    /// Called from the audio render thread. Must be synchronous and self-contained:
    /// the input `buffer`'s underlying memory may be invalid the moment this
    /// returns, so we always copy into a freshly-allocated buffer (either via
    /// AVAudioConverter or a manual memcpy when formats already match).
    nonisolated func feed(_ buffer: AVAudioPCMBuffer, time: AVAudioTime) {
        lock.lock()
        guard let cont = inputContinuation, let target = targetFormat else {
            lock.unlock()
            return
        }
        if converter == nil || converter?.inputFormat != buffer.format {
            converter = AVAudioConverter(from: buffer.format, to: target)
        }
        let conv = converter
        bufferCount += 1
        let cnt = bufferCount
        lock.unlock()

        if cnt == 1 || cnt % 50 == 0 {
            Log.write("LiveTranscriber: feed n=\(cnt) inFmt=\(buffer.format.sampleRate)Hz/\(buffer.format.channelCount)ch outFmt=\(target.sampleRate)Hz/\(target.channelCount)ch frames=\(buffer.frameLength)")
        }

        let converted: AVAudioPCMBuffer
        if buffer.format == target {
            // Even when formats match we still need a copy — the source memory
            // is owned by AVAudioEngine and may be recycled.
            guard let copy = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            if let src = buffer.int16ChannelData?[0], let dst = copy.int16ChannelData?[0] {
                memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Int16>.size)
            } else if let src = buffer.floatChannelData?[0], let dst = copy.floatChannelData?[0] {
                memcpy(dst, src, Int(buffer.frameLength) * MemoryLayout<Float>.size)
            } else {
                return
            }
            converted = copy
        } else if buffer.format.channelCount > 1 && target.channelCount == 1 &&
                  buffer.format.sampleRate == target.sampleRate {
            // VPIO delivers multi-channel (e.g. 3ch: voice + AEC refs) at the
            // same sample rate. Extract channel 0 directly — AVAudioConverter's
            // downmix averages all channels, diluting the voice signal.
            guard let copy = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: buffer.frameLength) else { return }
            copy.frameLength = buffer.frameLength
            let frames = Int(buffer.frameLength)
            if let src = buffer.floatChannelData?[0], let dst = copy.int16ChannelData?[0] {
                for i in 0..<frames {
                    let sample = max(-1.0, min(1.0, src[i]))
                    dst[i] = Int16(sample * 32767)
                }
            } else if let src = buffer.floatChannelData?[0], let dst = copy.floatChannelData?[0] {
                memcpy(dst, src, frames * MemoryLayout<Float>.size)
            } else if let src = buffer.int16ChannelData?[0], let dst = copy.int16ChannelData?[0] {
                memcpy(dst, src, frames * MemoryLayout<Int16>.size)
            } else {
                return
            }
            converted = copy
        } else {
            guard let conv else { return }
            let ratio = target.sampleRate / buffer.format.sampleRate
            let cap = AVAudioFrameCount(max(1, Double(buffer.frameLength) * ratio))
            guard let out = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: cap) else { return }
            var error: NSError?
            conv.convert(to: out, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }
            if let error {
                Log.write("LiveTranscriber: convert error \(error.localizedDescription)")
                return
            }
            converted = out
        }
        let cmtime = CMTime(value: time.sampleTime,
                            timescale: CMTimeScale(buffer.format.sampleRate))
        cont.yield(AnalyzerInput(buffer: converted, bufferStartTime: cmtime))
    }

    @MainActor
    func stop() async {
        lock.lock()
        isStopped = true
        let cont = inputContinuation
        let task = resultsTask
        let total = bufferCount
        inputContinuation = nil
        resultsTask = nil
        onPartialCallback = nil
        lock.unlock()

        // Finish input first so the analyzer can flush remaining audio,
        // then finalize before cancelling the drain task — otherwise we lose
        // any final results produced during finalization.
        cont?.finish()
        try? await analyzer?.finalizeAndFinishThroughEndOfInput()
        task?.cancel()
        analyzer = nil
        transcriber = nil
        converter = nil
        targetFormat = nil
        Log.write("LiveTranscriber: stopped totalBuffersFed=\(total)")
    }

    private func appendSegment(_ existing: String, _ next: String) -> String {
        if existing.isEmpty { return next }
        let last = existing.last!
        let needsSpace = !last.isWhitespace
        return existing + (needsSpace ? " " : "") + next
    }
}
#endif
