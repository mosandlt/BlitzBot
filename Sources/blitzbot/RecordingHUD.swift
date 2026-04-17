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
    // Strong references — the HUDController has the same lifetime as the app,
    // and SwiftUI's environmentObject needs concrete ObservableObjects (not
    // weak wrappers). Keeping them strong is fine at app-root level.
    private let profileStore: ProfileStore
    private let strongConfig: AppConfig
    private let privacyEngine: PrivacyEngine

    init(processor: ModeProcessor, config: AppConfig) {
        self.processor = processor
        self.recorder = processor.recorder
        self.config = config
        self.profileStore = config.profileStore
        self.strongConfig = config
        self.privacyEngine = config.privacyEngine
        processor.$status
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.handle(status: $0) }
            .store(in: &cancellables)
    }

    private func handle(status: ModeProcessor.Status) {
        switch status {
        case .aufnahme, .transkribiert, .formuliert:
            show()
        case .recovery:
            // Keep HUD open — user needs to pick a profile or let the timer run out.
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
            profileStore: profileStore,
            onStop: { [weak self] in self?.stopRecording() },
            onSwitch: { [weak self] mode in self?.switchMode(to: mode) },
            onCancel: { [weak self] in self?.cancelRecording() },
            onPause: { [weak self] in self?.pauseRecording() },
            onResume: { [weak self] in self?.resumeRecording() },
            onRetryWithProfile: { [weak self] profile in self?.retryRecovery(with: profile) },
            onCancelRecovery: { [weak self] in self?.cancelRecoveryFlow() }
        )
        .environmentObject(processor)
        .environmentObject(recorder)
        .environmentObject(strongConfig)
        .environmentObject(privacyEngine)

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

    private func retryRecovery(with profile: ConnectionProfile) {
        guard let config else { return }
        processor.retryWithProfile(profile, config: config)
    }

    /// Named `cancelRecoveryFlow` (not `cancelRecovery`) so it can't be confused
    /// with `cancelRecording()` above — they clean up different state machines.
    private func cancelRecoveryFlow() {
        processor.cancelRecovery()
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
    @ObservedObject var profileStore: ProfileStore
    let onStop: () -> Void
    let onSwitch: (Mode) -> Void
    let onCancel: () -> Void
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetryWithProfile: (ConnectionProfile) -> Void
    let onCancelRecovery: () -> Void

    var body: some View {
        Group {
            if case .recovery(let message) = processor.status {
                RecoveryView(
                    errorMessage: message,
                    context: processor.recoveryContext,
                    profiles: profileStore.profiles,
                    onRetry: onRetryWithProfile,
                    onCancel: onCancelRecovery
                )
            } else {
                normalContent
            }
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

    private var normalContent: some View {
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
                PrivacyToggleButton(compact: true)
                Text(timerString)
                    .font(.system(.title3, design: .monospaced).bold())
                    .foregroundStyle(.white)
            }

            // ── Controls row: Pause/Resume + voice badge + Auto-Stop clock ─────────────
            controlsRow
                .opacity(isRecording ? 1 : 0)

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

            // "Stimme erkannt" badge — centred between Pause and autoStopClock
            HStack(spacing: 3) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 5, height: 5)
                Text("Stimme erkannt")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.1))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5))
            )
            .opacity(processor.hasVoiceActivity && !processor.isPaused ? 1 : 0)
            .animation(.easeInOut(duration: 0.3), value: processor.hasVoiceActivity)

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
            ForEach(Mode.voiceModes) { mode in
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
        case .recovery(let m): return "Verbindungsfehler: \(m)"
        case .bereit:         return "Bereit"
        }
    }

    private var dotColor: Color {
        switch processor.status {
        case .aufnahme:                   return .red
        case .transkribiert, .formuliert: return .yellow
        case .fertig:                     return .green
        case .fehler, .recovery:          return .orange
        case .bereit:                     return .gray
        }
    }
}

// MARK: - Recovery view (inline fallback when LLM connection fails)

private struct RecoveryView: View {
    let errorMessage: String
    let context: ModeProcessor.RecoveryContext?
    let profiles: [ConnectionProfile]
    let onRetry: (ConnectionProfile) -> Void
    let onCancel: () -> Void

    @State private var selectedID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            Text(errorMessage)
                .font(.callout)
                .foregroundStyle(.white.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Text("Dein Text ist gesichert (auch in der Zwischenablage). Wähle ein anderes Profil, um es erneut zu versuchen.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)

            profileList

            footer
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
        .onAppear(perform: preselect)
        .onChange(of: context?.failedProfileID) { _ in preselect() }
    }

    // MARK: Subviews

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text("Verbindungsfehler")
                .font(.headline)
                .foregroundStyle(.white)
            Spacer()
            if let secs = context?.secondsLeft {
                CountdownPill(secondsLeft: secs)
            }
        }
    }

    private var profileList: some View {
        VStack(spacing: 4) {
            if profiles.isEmpty {
                Text("Keine Profile konfiguriert — lege eins in den Einstellungen an.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ForEach(profiles) { profile in
                    ProfileRow(
                        profile: profile,
                        isSelected: selectedID == profile.id,
                        isFailed: context?.failedProfileID == profile.id,
                        onTap: {
                            guard context?.failedProfileID != profile.id else { return }
                            selectedID = profile.id
                        }
                    )
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button(action: onCancel) {
                Text("Abbrechen")
                    .font(.system(.caption, design: .rounded).bold())
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.white.opacity(0.08))
                    )
                    .foregroundStyle(.white.opacity(0.85))
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: triggerRetry) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                    Text("Erneut senden")
                }
                .font(.system(.caption, design: .rounded).bold())
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(canRetry ? Color.yellow.opacity(0.85) : Color.white.opacity(0.12))
                )
                .foregroundStyle(canRetry ? .black : .white.opacity(0.5))
            }
            .buttonStyle(.plain)
            .disabled(!canRetry)
        }
    }

    // MARK: Helpers

    private var canRetry: Bool {
        guard let id = selectedID else { return false }
        return id != context?.failedProfileID
    }

    private func triggerRetry() {
        guard let id = selectedID,
              let profile = profiles.first(where: { $0.id == id }) else { return }
        onRetry(profile)
    }

    /// Pre-select the first non-failed profile so the user only clicks "Erneut senden".
    private func preselect() {
        let failedID = context?.failedProfileID
        if let current = selectedID,
           current != failedID,
           profiles.contains(where: { $0.id == current }) {
            return
        }
        selectedID = profiles.first(where: { $0.id != failedID })?.id
    }
}

private struct ProfileRow: View {
    let profile: ConnectionProfile
    let isSelected: Bool
    let isFailed: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.system(size: 14))
                    .foregroundStyle(isSelected ? Color.yellow : Color.white.opacity(0.45))

                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(profile.name)
                            .font(.system(.callout, design: .rounded).weight(.semibold))
                            .foregroundStyle(.white.opacity(isFailed ? 0.45 : 0.95))
                        if isFailed {
                            Text("fehlgeschlagen")
                                .font(.caption2.bold())
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Capsule().fill(Color.orange.opacity(0.25)))
                                .foregroundStyle(.orange)
                        }
                    }
                    Text(profileSubtitle)
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(isFailed ? 0.3 : 0.55))
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Color.yellow.opacity(0.12) : Color.white.opacity(0.04))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isSelected ? Color.yellow.opacity(0.5) : Color.white.opacity(0.08),
                                  lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isFailed)
        .opacity(isFailed ? 0.6 : 1)
    }

    private var profileSubtitle: String {
        let model = profile.preferredModel ?? "–"
        return "\(profile.provider.displayName) · \(model)"
    }
}

private struct CountdownPill: View {
    let secondsLeft: Int

    var body: some View {
        let urgent = secondsLeft <= 10
        HStack(spacing: 5) {
            Image(systemName: "timer")
                .font(.caption2.bold())
            Text("Auto-Verwerfen in \(secondsLeft)s")
                .font(.caption2.bold())
                .monospacedDigit()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule()
                .fill(urgent ? Color.orange.opacity(0.25) : Color.white.opacity(0.08))
        )
        .foregroundStyle(urgent ? .orange : .white.opacity(0.75))
        .animation(.easeInOut(duration: 0.2), value: secondsLeft)
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

    @State private var idleTimer: Timer?
    @State private var idlePhase: Double = 0

    var body: some View {
        Canvas { context, size in
            guard size.width > 0, size.height > 0 else { return }
            drawWaveform(context: context, size: size, midY: size.height / 2)
        }
        .onAppear { startIdleTimer() }
        .onDisappear { idleTimer?.invalidate() }
    }

    private func drawWaveform(context: GraphicsContext, size: CGSize, midY: CGFloat) {
        guard samples.count > 1 else { return }
        let count = samples.count
        let xStep = size.width / CGFloat(count - 1)
        let amplitude = midY * 0.88

        // When recording, always yellow regardless of current speech activity.
        // When not recording (idle / post-stop), use grey.
        let isYellow = active

        // Build paths (shared for fill and stroke)
        var fillPath = Path()
        var strokePath = Path()
        let gain: Float = 4.5
        for i in 0..<count {
            let x = CGFloat(i) * xStep
            let raw = active ? samples[i] * gain : samples[i] * 0.6
            let sampleVal = max(-1.0, min(1.0, raw))
            let y = midY - CGFloat(sampleVal) * amplitude
            if i == 0 {
                fillPath.move(to: CGPoint(x: x, y: y))
                strokePath.move(to: CGPoint(x: x, y: y))
            } else {
                fillPath.addLine(to: CGPoint(x: x, y: y))
                strokePath.addLine(to: CGPoint(x: x, y: y))
            }
        }
        fillPath.addLine(to: CGPoint(x: size.width, y: midY))
        fillPath.addLine(to: CGPoint(x: 0, y: midY))
        fillPath.closeSubpath()

        if isYellow {
            // Yellow fill + gradient stroke
            context.fill(fillPath, with: .color(Color.yellow.opacity(0.12)))
            let gradient = Gradient(stops: [
                .init(color: .orange.opacity(0.65), location: 0),
                .init(color: .yellow.opacity(0.95), location: 0.35),
                .init(color: .yellow.opacity(0.95), location: 0.65),
                .init(color: .orange.opacity(0.65), location: 1)
            ])
            context.stroke(
                strokePath,
                with: .linearGradient(gradient,
                                      startPoint: CGPoint(x: 0, y: midY),
                                      endPoint: CGPoint(x: size.width, y: midY)),
                lineWidth: 1.8
            )
        } else {
            // Grey stroke when not recording
            context.stroke(
                strokePath,
                with: .color(Color.white.opacity(0.22)),
                lineWidth: 1.4
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
