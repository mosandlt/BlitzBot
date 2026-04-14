import AVFoundation
import Foundation

final class AudioRecorder: ObservableObject {
    private let engine = AVAudioEngine()
    private var file: AVAudioFile?
    private(set) var currentURL: URL?
    @Published var level: Float = 0
    /// Rolling ring buffer of normalized PCM samples for waveform rendering.
    /// Always 300 entries, oldest first, values in [-1, 1].
    @Published var waveformSamples: [Float] = Array(repeating: 0, count: 300)
    private var lastLevelUpdate: TimeInterval = 0
    private var lastWaveformUpdate: TimeInterval = 0
    /// Ring buffer internals (not published directly — batched via waveformSamples)
    private var ringBuffer: [Float] = Array(repeating: 0, count: 300)
    private var ringWriteIdx: Int = 0

    func start() throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let url = tempDir.appendingPathComponent("blitzbot-\(UUID().uuidString).wav")
        currentURL = url

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

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

        let converter = AVAudioConverter(from: inputFormat,
                                         to: outFile.processingFormat)!

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self, let file = self.file else { return }
            let ratio = outFile.processingFormat.sampleRate / inputFormat.sampleRate
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio)
            guard let out = AVAudioPCMBuffer(pcmFormat: outFile.processingFormat,
                                             frameCapacity: capacity) else { return }
            var error: NSError?
            converter.convert(to: out, error: &error) { _, status in
                status.pointee = .haveData
                return buffer
            }
            if error == nil {
                try? file.write(from: out)
            }
            self.publishLevel(from: buffer)
        }

        engine.prepare()
        try engine.start()
        return url
    }

    func stop() -> URL? {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        file = nil
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
