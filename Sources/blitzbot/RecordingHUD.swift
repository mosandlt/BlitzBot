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
            onSwitch: { [weak self] mode in self?.switchMode(to: mode) }
        )
        .environmentObject(processor)
        .environmentObject(recorder)

        let host = NSHostingView(rootView: view)
        let size = NSSize(width: 560, height: 220)
        host.frame = NSRect(origin: .zero, size: size)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
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

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
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
            WaveformView(level: recorder.level, active: isRecording)
                .frame(height: 32)
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

    private var modeSwitcher: some View {
        HStack(spacing: 6) {
            ForEach(Mode.allCases) { mode in
                ModePill(mode: mode,
                         isActive: processor.activeMode == mode,
                         disabled: !canInteract,
                         action: { onSwitch(mode) })
            }
            Spacer(minLength: 4)
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
        case .aufnahme:       return "Aufnahme läuft — Hotkey erneut drücken zum Beenden"
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
    let level: Float
    let active: Bool

    private let barCount = 22
    @State private var phase: Double = 0
    @State private var timer: Timer?

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(0..<barCount, id: \.self) { i in
                Capsule()
                    .fill(gradient(for: i))
                    .frame(width: 6, height: barHeight(i))
            }
        }
        .frame(maxWidth: .infinity)
        .onAppear { start() }
        .onDisappear { timer?.invalidate() }
    }

    private func start() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { _ in
            phase += 0.25
        }
    }

    private func barHeight(_ i: Int) -> CGFloat {
        let base: CGFloat = 4
        guard active else { return base }
        let center = Double(barCount - 1) / 2
        let dist = abs(Double(i) - center) / center
        let envelope = 1.0 - pow(dist, 1.4) * 0.6
        let wobble = 0.5 + 0.5 * sin(phase + Double(i) * 0.6)
        let lvl = Double(max(0.05, level))
        let h = 4 + CGFloat(lvl * envelope * wobble) * 52
        return min(h, 34)
    }

    private func gradient(for i: Int) -> LinearGradient {
        LinearGradient(
            colors: [.yellow.opacity(0.9), .orange],
            startPoint: .top, endPoint: .bottom
        )
    }
}
