import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var checker: PermissionsChecker
    @EnvironmentObject var config: AppConfig
    @Environment(\.dismiss) private var dismiss

    @StateObject private var modelDownloader = ModelDownloader()
    @State private var showingModelDownload = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Willkommen bei blitzbot").font(.title2).bold()
                Text("Kurzer Check — danach kann's losgehen.")
                    .foregroundStyle(.secondary)
            }

            Divider()

            row(title: "Mikrofon",
                subtitle: "Damit blitzbot deine Sprache aufnehmen kann.",
                state: checker.microphone,
                actionTitle: actionTitle(for: checker.microphone, firstTime: "Erlauben"),
                action: { Task { await requestMic() } })

            row(title: "Bedienungshilfen",
                subtitle: "Damit blitzbot per Cmd+V in die aktive App einfügen kann.",
                state: checker.accessibility,
                actionTitle: actionTitle(for: checker.accessibility, firstTime: "Öffnen"),
                action: handleAccessibility)

            row(title: "Whisper-Binary",
                subtitle: config.whisperBinary,
                state: checker.whisperBinary,
                actionTitle: "Terminal",
                action: copyBinarySetupCommand)

            row(title: "Whisper-Modell",
                subtitle: modelSubtitle,
                state: checker.whisperModel,
                actionTitle: "Jetzt laden",
                action: openModelDownload)

            Divider()

            HStack {
                Button("Erneut prüfen") { checker.refresh(config: config) }
                Spacer()
                Button("Weiter") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!checker.allGood)
            }
        }
        .padding(24)
        .frame(width: 520)
        .onAppear { checker.refresh(config: config) }
        .sheet(isPresented: $showingModelDownload) {
            ModelDownloadSheet(downloader: modelDownloader) {
                // Completion callback: refresh permissions so "Whisper-Modell" turns green.
                checker.refresh(config: config)
                showingModelDownload = false
            }
        }
    }

    private var modelSubtitle: String {
        if checker.whisperModel == .ok {
            return config.whisperModel
        }
        return "\(config.whisperModel) — ~1.5 GB Download"
    }

    private func openModelDownload() {
        showingModelDownload = true
        Task { await modelDownloader.check() }
    }

    private func row(title: String, subtitle: String, state: PermissionsChecker.State,
                     actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            statusIcon(state)
                .frame(width: 20, alignment: .center)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer()
            if state != .ok {
                Button(actionTitle, action: action)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(_ state: PermissionsChecker.State) -> some View {
        switch state {
        case .ok:      Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .missing: Image(systemName: "xmark.octagon.fill").foregroundStyle(.red)
        case .unknown: Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
        }
    }

    private func actionTitle(for state: PermissionsChecker.State, firstTime: String) -> String {
        state == .unknown ? firstTime : "In Einstellungen öffnen"
    }

    private func requestMic() async {
        if checker.microphone == .unknown {
            await checker.requestMicrophone()
        } else {
            checker.openMicrophonePane()
        }
        checker.refresh(config: config)
    }

    private func handleAccessibility() {
        if checker.accessibility == .unknown {
            checker.promptAccessibility()
        } else {
            checker.openAccessibilityPane()
        }
        checker.refresh(config: config)
    }

    private func copyBinarySetupCommand() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("brew install whisper-cpp", forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }
}

/// Modal sheet that streams the Whisper model into place with a progress bar
/// and a single cancel button. Dismisses itself via the `onFinish` callback
/// once the downloader reports `.done`.
struct ModelDownloadSheet: View {
    @ObservedObject var downloader: ModelDownloader
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.title)
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Whisper-Modell laden").font(.title3.bold())
                    Text("\(downloader.model.rawValue) · ~\(downloader.model.sizeMB) MB · HuggingFace").font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            content

            Divider()

            HStack {
                Spacer()
                footerButtons
            }
        }
        .padding(22)
        .frame(width: 480)
    }

    @ViewBuilder
    private var content: some View {
        switch downloader.state {
        case .idle, .checking:
            HStack {
                ProgressView().controlSize(.small)
                Text("Prüfe Server …").font(.callout)
            }
        case .needsDownload(let bytes):
            VStack(alignment: .leading, spacing: 6) {
                Text("Bereit zum Download.").font(.callout)
                if bytes > 0 {
                    Text(formatSize(bytes))
                        .font(.caption).foregroundStyle(.secondary)
                }
                Text("Der Download läuft solange dieses Fenster offen ist. Wenn du abbrichst, wird die Teildatei verworfen.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .downloading(let done, let total):
            VStack(alignment: .leading, spacing: 8) {
                if total > 0 {
                    ProgressView(value: Double(done), total: Double(total))
                    Text("\(formatSize(done)) von \(formatSize(total))")
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                } else {
                    ProgressView()
                    Text(formatSize(done))
                        .font(.caption).foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        case .verifying:
            HStack {
                ProgressView().controlSize(.small)
                Text("Prüfe Datei …").font(.callout)
            }
        case .done:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Modell geladen.").fontWeight(.medium)
            }
        case .error(let msg):
            VStack(alignment: .leading, spacing: 6) {
                Label(msg, systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
                Text("Du kannst es erneut versuchen oder das Modell manuell nach \(downloader.destinationPath) legen.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var footerButtons: some View {
        switch downloader.state {
        case .idle, .checking, .verifying:
            Button("Abbrechen") { onFinish() }
        case .needsDownload:
            Button("Abbrechen") { onFinish() }
            Button("Download starten") { downloader.startDownload() }
                .buttonStyle(.borderedProminent)
        case .downloading:
            Button("Abbrechen") {
                downloader.cancel()
                onFinish()
            }
        case .done:
            Button("Fertig") { onFinish() }
                .buttonStyle(.borderedProminent)
        case .error:
            Button("Schließen") { onFinish() }
            Button("Erneut versuchen") { downloader.startDownload() }
                .buttonStyle(.borderedProminent)
        }
    }

    private func formatSize(_ bytes: Int64) -> String {
        let fmt = ByteCountFormatter()
        fmt.countStyle = .file
        return fmt.string(fromByteCount: bytes)
    }
}
