import AppKit
import Combine
import SwiftUI

@MainActor
final class RecordingHUDController {
    private var panel: NSPanel?
    private var cancellables: Set<AnyCancellable> = []
    private let processor: ModeProcessor
    private let recorder: AudioRecorder
    private weak var config: AppConfig?

    init(processor: ModeProcessor, config: AppConfig) {
        self.processor = processor
        self.recorder = processor.recorder
        self.config = config
        processor.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handle(status: $0) }
            .store(in: &cancellables)
    }

    private func handle(status: ModeProcessor.Status) {
        switch status {
        case .aufnahme, .transkribiert, .formuliert:
            show()
        case .fertig:
            hideAfter(delay: 0.8)
        case .fehler:
            hideAfter(delay: 1.6)
        case .bereit:
            hide()
        }
    }

    private func show() {
        if panel == nil { panel = makePanel() }
        guard let panel else { return }
        centerOnActiveScreen(panel)
        panel.orderFrontRegardless()
    }

    private func hide() {
        panel?.orderOut(nil)
    }

    private func hideAfter(delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            switch self.processor.status {
            case .fertig, .fehler, .bereit: self.hide()
            default: break
            }
        }
    }

    private func makePanel() -> NSPanel {
        let view = HUDView(
            onStop: { [weak self] in self?.stopRecording() },
            onSwitch: { [weak self] mode in self?.switchMode(to: mode) },
            onCancel: { [weak self] in self?.cancelRecording() },
            onPause: { [weak self] in self?.pauseRecording() },
            onResume: { [weak self] in self?.resumeRecording() }
        )
        .environmentObject(processor)
        .environmentObject(recorder)

        let host = NSHostingView(rootView: view)
        let size = NSSize(width: 560, height: 300)
        host.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.ignoresMouseEvents = false
        panel.hidesOnDeactivate = false
        panel.contentView = host
        return panel
    }

    private func stopRecording() {
        guard let mode = processor.activeMode, let config else { return }
        processor.toggle(mode: mode, config: config)
    }

    private func cancelRecording() {
        processor.cancel()
    }

    private func pauseRecording() {
        guard let config else { return }
        processor.pauseRecording(config: config)
    }

    private func resumeRecording() {
        guard let config else { return }
        processor.resumeRecording(config: config)
    }

    private func switchMode(to mode: Mode) {
        guard let config else { return }
        processor.toggle(mode: mode, config: config)
    }

    private func centerOnActiveScreen(_ panel: NSPanel) {
        let screen = NSScreen.main ?? NSScreen.screens.first
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.midY - size.height / 2
        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: true)
    }
}

private struct HUDView: View {
    @EnvironmentObject var processor: ModeProcessor
    @EnvironmentObject var recorder: AudioRecorder
    let onStop: () -> Void
    let onSwitch: (Mode) -> Void
    let onCancel: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            // ── Header row ──────────────────────────────────────────────
            HStack(spacing: 8) {
                // X — Abbrechen (oben links)
                Button(action: onCancel) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(0.12)))
                        .foregroundStyle(.white.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("Aufnahme abbrechen (kein Text wird eingefügt)")

                Image(systemName: processor.activeMode?.symbolName ?? "bolt.fill")
                    .foregroundStyle(.yellow)
                Text(processor.activeMode?.displayName ?? "blitzbot")
                    .font(.headline).foregroundStyle(.white)
                if let lang = processor.detectedLanguage {
                    Text(lang.uppercased())
                        .font(.caption2.bold())
                        .padding(.horizontal, 6).padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.15)))
                        .foregroundStyle(.white.opacity(0.9))
                }
                Spacer()
                Text(timerString)
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.white)
            }

            // ── Controls row: Pause/Resume + Auto-Stop clock ─────────────
            if isRecording {
                controlsRow
            }

            // ── Real waveform ────────────────────────────────────────────
            WaveformView(
                samples: recorder.waveformSamples,
                level: recorder.level,
                active: isRecording && !processor.isPaused
            )
            .frame(height: 72)

            // ── Silence banner — reserved height, fades in/out (no layout jump) ──
            autoStopBannerReserved

            Text(statusText)
                .font(.caption).foregroundStyle(.white.opacity(0.75))
                .frame(maxWidth: .infinity, alignment: .leading)

            modeSwitcher
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.black.opacity(0.85))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(dotColor.opacity(0.6), lineWidth: 1.2)
                )
        )
    }

    /// Fixed-height slot — avoids layout jumps. Banner fades in/out via opacity.
    private var autoStopBannerReserved: some View {
        let secs = processor.autoStopSecondsLeft
        let show = isRecording && processor.showSilenceBanner && secs != nil
        return autoStopBanner(secondsLeft: secs ?? 0)
            .opacity(show ? 1 : 0)
            .animation(.easeInOut(duration: 0.35), value: show)
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            // Pause / Resume pill
            Button(action: { processor.isPaused ? onResume() : onPause() }) {
                HStack(spacing: 4) {
                    Image(systemName: processor.isPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(processor.isPaused ? "Weiter" : "Pause")
                        .font(.system(.caption2, design: .rounded).bold())
                }
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(processor.isPaused
                              ? Color.yellow.opacity(0.25)
                              : Color.white.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(processor.isPaused ? 0.5 : 0.2), lineWidth: 1)
                )
                .foregroundStyle(.white.opacity(0.9))
            }
            .buttonStyle(.plain)

            Spacer()

            // Auto-Stop progress clock (only while not paused)
            if !processor.isPaused, let secs = processor.autoStopSecondsLeft {
                autoStopClock(secondsLeft: secs)
            }
        }
    }

    @ViewBuilder
    private func autoStopClock(secondsLeft: Int) -> some View {
        let total = processor.autoStopTimeoutForDisplay
        let progress = total > 0 ? max(0, min(1, Double(secondsLeft) / total)) : 1.0
        let urgent = secondsLeft <= 5
        HStack(spacing: 6) {
            // Circular countdown
            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.12), lineWidth: 2.5)
                    .frame(width: 20, height: 20)
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        urgent ? Color.orange : Color.white.opacity(0.55),
                        style: StrokeStyle(lineWidth: 2.5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 20, height: 20)
                    .animation(.linear(duration: 0.1), value: progress)
            }
            Text("\(secondsLeft)s")
                .font(.system(.caption2, design: .monospaced).bold())
                .foregroundStyle(urgent ? .orange : .white.opacity(0.65))
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(urgent ? Color.orange.opacity(0.15) : Color.white.opacity(0.06))
        )
    }

    private var modeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases) { mode in
                ModePill(mode: mode,
                         isActive: processor.activeMode == mode,
                         disabled: !canInteract,
                         action: { onSwitch(mode) })
            }
            Spacer(minLength: 4)
            if isRecording {
                autoExecuteToggle
            }
            Button(action: onStop) {
                HStack(spacing: 4) {
                    Image(systemName: "stop.fill")
                    Text("Stop")
                }
                .font(.system(.caption, design: .rounded).bold())
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(isRecording ? Color.red : Color.red.opacity(0.4))
                )
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(!canInteract)
        }
    }

    @ViewBuilder
    private func autoStopBanner(secondsLeft: Int) -> some View {
        let urgent = secondsLeft <= 5
        HStack(spacing: 6) {
            Image(systemName: urgent ? "timer.circle.fill" : "timer")
                .font(.caption2.bold())
            Text(urgent
                 ? "Auto-Stop in \(secondsLeft)s"
                 : "Stille erkannt — Auto-Stop in \(secondsLeft)s")
                .font(.caption2.bold())
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(urgent ? Color.orange.opacity(0.25) : Color.white.opacity(0.08))
        )
        .foregroundStyle(urgent ? .orange : .white.opacity(0.65))
        .animation(.easeInOut(duration: 0.2), value: secondsLeft)
    }

    private var autoExecuteToggle: some View {
        Button {
            processor.autoExecute.toggle()
        } label: {
            Image(systemName: processor.autoExecute ? "return.left" : "return")
                .font(.system(size: 12, weight: .bold))
                .frame(width: 30, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(processor.autoExecute
                              ? Color.yellow.opacity(0.25)
                              : Color.white.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.white.opacity(processor.autoExecute ? 0.5 : 0), lineWidth: 1)
                )
                .foregroundStyle(processor.autoExecute ? .white : .white.opacity(0.6))
        }
        .buttonStyle(.plain)
        .help("Nach dem Einfügen automatisch Return drücken (z. B. für ChatGPT). Gilt nur für diese Aufnahme.")
    }

    private var canInteract: Bool {
        switch processor.status {
        case .aufnahme: return true
        default:        return false
        }
    }

    private var isRecording: Bool {
        if case .aufnahme = processor.status { return true }; return false
    }

    private var timerString: String {
        let t = Int(processor.elapsed)
        return String(format: "%02d:%02d", t / 60, t % 60)
    }

    private var statusText: String {
        switch processor.status {
        case .aufnahme:
            return processor.isPaused
                ? "Pausiert — Weiter zum Fortsetzen"
                : "Aufnahme läuft — Hotkey erneut drücken zum Beenden"
        case .transkribiert:  return "Transkribiere…"
        case .formuliert:     return "Formuliere…"
        case .fertig:         return "Fertig — Text eingefügt"
        case .fehler(let m):  return "Fehler: \(m)"
        case .bereit:         return "Bereit"
        }
    }

    private var dotColor: Color {
        switch processor.status {
        case .aufnahme:                   return .red
        case .transkribiert, .formuliert: return .yellow
        case .fertig:                     return .green
        case .fehler:                     return .orange
        case .bereit:                     return .gray
        }
    }
}

private struct ModePill: View {
    let mode: Mode
    let isActive: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.symbolName)
                    .font(.caption2)
                Text(mode.displayName)
                    .font(.system(.caption2, design: .rounded).bold())
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Color.white.opacity(isActive ? 0.5 : 0), lineWidth: 1)
            )
            .foregroundStyle(isActive ? .white : .white.opacity(0.78))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(disabled)
        .opacity(disabled ? 0.4 : 1)
    }

    private var background: Color {
        if isActive { return .yellow.opacity(0.25) }
        if hovering { return .white.opacity(0.12) }
        return .white.opacity(0.05)
    }
}

private struct WaveformView: View {
    let samples: [Float]
    let level: Float
    let active: Bool

    /// Smoothed voice-activity weight: 1.0 = voice, 0.0 = silence.
    /// Animates between states for a soft color transition.
    @State private var voiceWeight: Double = 0
    @State private var idlePhase: Double = 0
    @State private var idleTimer: Timer?

    private var hasVoice: Bool { active && level > 0.015 }

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            let midY = size.height / 2
            drawWaveform(context: context, size: size, midY: midY)
        }
        .animation(.easeInOut(duration: 0.4), value: voiceWeight)
        .onChange(of: hasVoice) { newValue in
            withAnimation(.easeInOut(duration: 0.45)) {
                voiceWeight = newValue ? 1.0 : 0.0
            }
        }
        .onAppear {
            voiceWeight = hasVoice ? 1.0 : 0.0
            startIdleTimer()
        }
        .onDisappear { idleTimer?.invalidate() }
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize, midY: CGFloat) {
        guard samples.count > 1 else { return }
        let count = samples.count
        let xStep = size.width / CGFloat(count - 1)
        let amplitude = midY * 0.88

        // Color: interpolate yellow ↔ grey based on voiceWeight
        let fillOpacity = voiceWeight * 0.12

        // Fill path
        var fillPath = Path()
        for i in 0..<count {
            let x = CGFloat(i) * xStep
            // When idle/silent, show a very gentle low-amplitude version of the waveform
            let sampleVal = active ? samples[i] : samples[i] * 0.15
            let y = midY - CGFloat(sampleVal) * amplitude
            if i == 0 { fillPath.move(to: CGPoint(x: x, y: y)) }
            else { fillPath.addLine(to: CGPoint(x: x, y: y)) }
        }
        fillPath.addLine(to: CGPoint(x: size.width, y: midY))
        fillPath.addLine(to: CGPoint(x: 0, y: midY))
        fillPath.closeSubpath()
        if fillOpacity > 0.005 {
            context.fill(fillPath, with: .color(Color.yellow.opacity(fillOpacity)))
        }

        // Stroke path
        var strokePath = Path()
        for i in 0..<count {
            let x = CGFloat(i) * xStep
            let sampleVal = active ? samples[i] : samples[i] * 0.15
            let y = midY - CGFloat(sampleVal) * amplitude
            if i == 0 { strokePath.move(to: CGPoint(x: x, y: y)) }
            else { strokePath.addLine(to: CGPoint(x: x, y: y)) }
        }

        if voiceWeight > 0.01 {
            // Yellow gradient with fade at edges when voice is active
            let gradient = Gradient(stops: [
                .init(color: .orange.opacity(0.6 * voiceWeight), location: 0),
                .init(color: .yellow.opacity(0.95 * voiceWeight), location: 0.35),
                .init(color: .yellow.opacity(0.95 * voiceWeight), location: 0.65),
                .init(color: .orange.opacity(0.6 * voiceWeight), location: 1)
            ])
            context.stroke(
                strokePath,
                with: .linearGradient(gradient,
                                      startPoint: .init(x: 0, y: midY),
                                      endPoint: .init(x: size.width, y: midY)),
                lineWidth: 1.8
            )
        }
        // Grey overlay — fades in as voice fades out
        if voiceWeight < 0.99 {
            context.stroke(
                strokePath,
                with: .color(Color.white.opacity(0.25 * (1 - voiceWeight))),
                lineWidth: 1.5
            )
        }
    }

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 20, repeats: true) { _ in
            idlePhase += 0.08
        }
    }
}
