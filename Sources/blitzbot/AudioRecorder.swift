import AVFoundation
import CoreAudio
import Foundation

final class AudioRecorder: ObservableObject {
    /// Replaced after every VPIO recording. setVoiceProcessingEnabled(false)
    /// + engine.reset() does NOT release the underlying AUVoiceProcessing
    /// audio unit — the system-wide output ducking stays armed until the
    /// last strong reference drops. Recreating the engine deallocates the AU
    /// and clears the duck (Apple Developer Forums 721535, open since macOS 11).
    private var engine = AVAudioEngine()
    private var file: AVAudioFile?
    private(set) var currentURL: URL?
    /// Optional second consumer of every captured PCM buffer. ModeProcessor
    /// installs this to feed Apple's live SpeechTranscriber alongside the WAV
    /// writer. nil = no live transcription, default behavior unchanged.
    var bufferTap: ((AVAudioPCMBuffer, AVAudioTime) -> Void)?
    @Published var level: Float = 0
    /// Rolling ring buffer of normalized PCM samples for waveform rendering.
    /// Always 300 entries, oldest first, values in [-1, 1].
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 300)
    private var lastLevelUpdate: TimeInterval = 0
    private var lastWaveformUpdate: TimeInterval = 0
    /// Ring buffer internals (not published directly — batched via waveformSamples)
    private var ringBuffer: [Float] = Array(repeating: 0, count: 300)
    private var ringWriteIdx: Int = 0
    /// Observer token for AVAudioEngineConfigurationChange. Bluetooth devices
    /// (e.g. AirPods) switch from A2DP (output-only, high quality) to HSP/HFP
    /// (headset, lower quality) when audio input starts. This changes the
    /// hardware sample rate and stops the engine. We reinstall the tap with the
    /// new format and restart the engine so the recording continues uninterrupted.
    private var engineConfigObserver: NSObjectProtocol?
    /// Latched for the current recording so the config-change observer can
    /// re-apply VPIO on the new audio unit after a Bluetooth profile switch.
    private var voiceIsolationActive: Bool = false

    func start(preferredMicUID: String? = nil, voiceIsolation: Bool = false) throws -> URL {
        // Guard: if a tap is still installed from a previous (possibly aborted) recording,
        // remove it before installing a new one. installTap on an already-tapped bus throws
        // an NSException that Swift cannot catch, causing an immediate crash.
        let input = engine.inputNode
        if engine.isRunning || currentURL != nil {
            input.removeTap(onBus: 0)
            engine.stop()
            file = nil
            currentURL = nil
        }

        // Apply mic preference. Must run BEFORE the first inputFormat read so the
        // sample rate / channel layout matches the device we'll actually capture from.
        applyPreferredMic(preferredMicUID, input: input)
        // VPIO must be toggled before the engine starts and before installTap reads
        // the input format — enabling it can change the channel layout / sample rate.
        applyVoiceIsolation(voiceIsolation, input: input)

        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("blitzbot-\(UUID().uuidString).wav")
        currentURL = url

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false
        ]
        let outFile = try AVAudioFile(forWriting: url, settings: settings,
                                      commonFormat: .pcmFormatInt16, interleaved: true)
        file = outFile

        installTap(outFile: outFile)

        engine.prepare()
        try engine.start()

        // When a Bluetooth device changes its audio profile (A2DP → HSP/HFP) the
        // engine stops itself and the hardware sample rate changes. A plain
        // engine.start() fails with -10868 because the tap was registered for the
        // old format. We remove the tap, reinstall it with the current (new) input
        // format, and restart the engine. The WAV file stays open — recording
        // continues seamlessly.
        engineConfigObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            guard let self, let outFile = self.file else { return }
            let newFmt = self.engine.inputNode.outputFormat(forBus: 0)
            Log.write("AudioRecorder: config change → new input \(newFmt.sampleRate)Hz/\(newFmt.channelCount)ch — reinstalling tap")
            self.engine.inputNode.removeTap(onBus: 0)
            // Re-apply VPIO — switching Bluetooth profiles (A2DP → HFP) replaces
            // the underlying audio unit, which loses the voice-processing flag.
            self.applyVoiceIsolation(self.voiceIsolationActive, input: self.engine.inputNode)
            self.installTap(outFile: outFile)
            self.engine.prepare()
            do {
                try self.engine.start()
                Log.write("AudioRecorder: engine restarted after config change")
            } catch {
                Log.write("AudioRecorder: engine restart failed: \(error)")
            }
        }

        return url
    }

    /// Install an audio tap on the engine's input node. When VPIO is active the
    /// node's reported format can be stale, so we pass `format: nil` and create
    /// the converter lazily from the first buffer's actual format.
    private func installTap(outFile: AVAudioFile) {
        let input = engine.inputNode
        let outProcessingFormat = outFile.processingFormat
        let useVPIO = voiceIsolationActive

        // When VPIO is off, we can trust outputFormat and pre-create the converter.
        // When VPIO is on, defer — the actual delivery format may differ from what
        // outputFormat(forBus:0) reports until the first render callback fires.
        let tapFormat: AVAudioFormat?
        var converter: AVAudioConverter?

        if useVPIO {
            tapFormat = nil
            Log.write("AudioRecorder: tap installed (VPIO, format deferred) → 16kHz/1ch")
        } else {
            let inputFormat = input.outputFormat(forBus: 0)
            tapFormat = inputFormat
            converter = AVAudioConverter(from: inputFormat, to: outProcessingFormat)
            if converter == nil {
                Log.write("AudioRecorder: cannot create converter \(inputFormat.sampleRate)Hz → \(outProcessingFormat.sampleRate)Hz")
                return
            }
            Log.write("AudioRecorder: tap installed \(inputFormat.sampleRate)Hz/\(inputFormat.channelCount)ch → 16kHz/1ch")
        }

        // VPIO at 16kHz with 4096 frames = 256ms per buffer (~4 callbacks/sec) →
        // waveform stutters. 1024 frames at 16kHz = 64ms (~15 callbacks/sec).
        let tapBufferSize: AVAudioFrameCount = useVPIO ? 1024 : 4096
        input.installTap(onBus: 0, bufferSize: tapBufferSize, format: tapFormat) { [weak self] buffer, when in
            guard let self, let file = self.file else { return }

            let frameCount = buffer.frameLength
            guard frameCount > 0 else { return }

            // VPIO delivers multi-channel: ch0 = processed voice, the rest = AEC
            // reference signals. AVAudioConverter's standard downmix averages all
            // channels, which dilutes voice (~1/N amplitude on N-channel devices)
            // and mixes in reference noise — Whisper then hallucinates from the
            // resulting mush. Pre-extract ch0 to a mono Float buffer; the converter
            // path then handles only sample-rate conversion + Float→Int16.
            let workBuffer: AVAudioPCMBuffer
            if useVPIO && buffer.format.channelCount > 1 {
                guard let mono = AudioRecorder.extractChannel0AsMonoFloat(from: buffer) else { return }
                workBuffer = mono
            } else {
                workBuffer = buffer
            }

            // Lazily (re)create the converter once the real input format is known.
            // Under VPIO we deferred this; if the source format ever changes mid-
            // recording (Bluetooth profile switch, mic swap), the input format on
            // the existing converter no longer matches and we rebuild it.
            if converter == nil || converter?.inputFormat != workBuffer.format {
                let actualFormat = workBuffer.format
                let extractNote = (useVPIO && buffer.format.channelCount > 1)
                    ? " (VPIO ch0-extract from \(buffer.format.channelCount)ch)"
                    : ""
                Log.write("AudioRecorder: first buffer fmt=\(actualFormat.sampleRate)Hz/\(actualFormat.channelCount)ch frames=\(frameCount)\(extractNote)")
                converter = AVAudioConverter(from: actualFormat, to: outProcessingFormat)
                if converter == nil {
                    Log.write("AudioRecorder: converter creation failed — dropping buffers")
                    return
                }
            } else if self.ringWriteIdx == 0 {
                Log.write("AudioRecorder: tap first call fmt=\(buffer.format.sampleRate)Hz frames=\(frameCount)")
            }

            guard let conv = converter else { return }
            let ratio = outProcessingFormat.sampleRate / workBuffer.format.sampleRate
            let capacity = AVAudioFrameCount(max(1, Double(frameCount) * ratio))
            guard let out = AVAudioPCMBuffer(pcmFormat: outProcessingFormat,
                                             frameCapacity: capacity) else { return }
            var error: NSError?
            conv.convert(to: out, error: &error) { _, status in
                status.pointee = .haveData
                return workBuffer
            }
            if error == nil {
                try? file.write(from: out)
            }
            self.publishLevel(from: workBuffer)
            self.bufferTap?(workBuffer, when)
        }
    }

    /// Reduces a multi-channel PCM buffer to a mono Float32 buffer using only
    /// channel 0 (the VPIO-processed voice channel). Sample rate is preserved —
    /// the caller's AVAudioConverter handles SRC + Float→Int16 in a second pass.
    /// Required because AVAudioConverter's built-in downmix averages all input
    /// channels, mixing AEC reference signals into the voice output.
    private static func extractChannel0AsMonoFloat(from buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let srcFormat = buffer.format
        guard let monoFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                             sampleRate: srcFormat.sampleRate,
                                             channels: 1,
                                             interleaved: false) else { return nil }
        let frames = Int(buffer.frameLength)
        guard frames > 0,
              let out = AVAudioPCMBuffer(pcmFormat: monoFormat,
                                         frameCapacity: AVAudioFrameCount(frames)) else { return nil }
        out.frameLength = AVAudioFrameCount(frames)
        guard let dst = out.floatChannelData?[0] else { return nil }
        let stride = srcFormat.isInterleaved ? Int(srcFormat.channelCount) : 1
        if let chData = buffer.floatChannelData {
            let src = chData[0]
            if stride == 1 {
                memcpy(dst, src, frames * MemoryLayout<Float>.size)
            } else {
                for i in 0..<frames { dst[i] = src[i * stride] }
            }
        } else if let chData = buffer.int16ChannelData {
            let src = chData[0]
            let scale: Float = 1.0 / 32768.0
            for i in 0..<frames {
                dst[i] = Float(src[i * stride]) * scale
            }
        } else {
            return nil
        }
        return out
    }

    func stop() -> URL? {
        if let obs = engineConfigObserver {
            NotificationCenter.default.removeObserver(obs)
            engineConfigObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        // VPIO duck teardown — strict order: VP off BEFORE stop so the AU emits
        // its "restore other audio" event, then drop the engine reference so the
        // AUVoiceProcessing unit is actually deallocated. setVoiceProcessingEnabled
        // + reset alone keeps the AU alive (the engine still holds it), and the
        // system-wide output ducking remains armed until app quit. Recreating the
        // engine here clears the duck reliably.
        let wasVPIO = voiceIsolationActive
        if wasVPIO {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(false)
                Log.write("AudioRecorder: voice processing disabled on stop")
            } catch {
                Log.write("AudioRecorder: setVoiceProcessingEnabled(false) on stop failed — \(error)")
            }
            voiceIsolationActive = false
        }
        engine.stop()
        engine.reset()
        if wasVPIO {
            engine = AVAudioEngine()
            Log.write("AudioRecorder: engine recreated to release VPIO audio unit")
        }
        file = nil
        bufferTap = nil
        let url = currentURL
        currentURL = nil
        DispatchQueue.main.async {
            self.level = 0
            self.waveformSamples = Array(repeating: 0, count: 300)
        }
        ringBuffer = Array(repeating: 0, count: 300)
        ringWriteIdx = 0
        return url
    }

    func pause() {
        engine.pause()
        DispatchQueue.main.async {
            self.level = 0
            self.waveformSamples = Array(repeating: 0, count: 300)
        }
    }

    func resume() throws {
        try engine.start()
    }

    /// Enables or disables Apple's Voice Processing I/O on the input node.
    /// Provides noise suppression, AEC and AGC — the same stack iMessage and
    /// FaceTime use. Best-effort: VPIO can fail on aggregate devices or some
    /// USB interfaces; in that case we leave the engine raw and continue.
    /// Safe to call from start() and from the config-change observer.
    private func applyVoiceIsolation(_ enabled: Bool, input: AVAudioInputNode) {
        voiceIsolationActive = enabled
        guard input.isVoiceProcessingEnabled != enabled else { return }
        do {
            try input.setVoiceProcessingEnabled(enabled)
            Log.write("AudioRecorder: voice processing \(enabled ? "enabled" : "disabled")")
        } catch {
            Log.write("AudioRecorder: setVoiceProcessingEnabled(\(enabled)) failed — \(error)")
            // Reflect actual state in case the call partially mutated.
            voiceIsolationActive = input.isVoiceProcessingEnabled
        }
    }

    /// Sets the input device on the underlying HAL audio unit. nil = leave alone
    /// (system default). If the stored UID no longer maps to a connected device,
    /// log and fall through silently — recording continues on the system default.
    private func applyPreferredMic(_ uid: String?, input: AVAudioInputNode) {
        guard let uid, !uid.isEmpty else { return }
        guard var deviceID = AudioInputDevices.deviceID(forUID: uid) else {
            Log.write("AudioRecorder: preferred mic UID not found, falling back to default: \(uid)")
            return
        }
        guard let unit = input.audioUnit else { return }
        let size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioUnitSetProperty(unit,
                                          kAudioOutputUnitProperty_CurrentDevice,
                                          kAudioUnitScope_Global,
                                          0,
                                          &deviceID,
                                          size)
        if status != noErr {
            Log.write("AudioRecorder: AudioUnitSetProperty failed status=\(status) for uid=\(uid)")
        } else {
            Log.write("AudioRecorder: input device set to uid=\(uid) id=\(deviceID)")
        }
    }

    private func publishLevel(from buffer: AVAudioPCMBuffer) {
        guard let data = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }

        // RMS level for waveform activity
        var sum: Float = 0
        for i in 0..<count { sum += data[i] * data[i] }
        let rms = sqrt(sum / Float(count))
        let db = 20 * log10(max(rms, 1e-7))
        let norm = max(0, min(1, (db + 60) / 60))

        // Feed ring buffer: pick up to 10 representative samples per tap call
        let step = max(1, count / 10)
        for i in stride(from: 0, to: count, by: step) {
            ringBuffer[ringWriteIdx % 300] = data[i]
            ringWriteIdx += 1
        }

        let now = CFAbsoluteTimeGetCurrent()
        // Level: throttled to 25fps
        if now - lastLevelUpdate > 0.04 {
            lastLevelUpdate = now
            DispatchQueue.main.async { self.level = norm }
        }
        // Waveform samples: throttled to 20fps
        if now - lastWaveformUpdate > 0.05 {
            lastWaveformUpdate = now
            let idx = ringWriteIdx % 300
            let ordered = Array(ringBuffer[idx...]) + Array(ringBuffer[..<idx])
            DispatchQueue.main.async { self.waveformSamples = ordered }
        }
    }
}
