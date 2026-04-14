import SwiftUI

struct PermissionsView: View {
    @EnvironmentObject var checker: PermissionsChecker
    @EnvironmentObject var config: AppConfig
    @Environment(\.dismiss) private var dismiss

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
                action: copySetupCommand)

            row(title: "Whisper-Modell",
                subtitle: config.whisperModel,
                state: checker.whisperModel,
                actionTitle: "Terminal",
                action: copySetupCommand)

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

    private func copySetupCommand() {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString("cd \"$(dirname \"$0\")\" && ./setup-whisper.sh", forType: .string)
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
    }
}
