import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject var processor: ModeProcessor
    @EnvironmentObject var config: AppConfig
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ForEach(Mode.allCases) { mode in
                ModeRow(mode: mode)
                    .environmentObject(processor)
                    .environmentObject(config)
                if mode != Mode.allCases.last { Divider().opacity(0.3) }
            }
            Divider()
            footer
        }
        .frame(width: 320)
        .padding(.vertical, 6)
    }

    private var header: some View {
        HStack {
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            Text("blitzbot").font(.headline)
            Spacer()
            statusIndicator
            Button { openWindow(id: "settings") } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var statusIndicator: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(processor.status.label).font(.caption)
        }
    }

    private var statusColor: Color {
        switch processor.status {
        case .bereit, .fertig: return .green
        case .aufnahme:        return .red
        case .transkribiert, .formuliert: return .yellow
        case .fehler:          return .orange
        }
    }

    private var footer: some View {
        HStack {
            if !config.hasAPIKey {
                Label("Kein API-Key", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
            Spacer()
            Button("Beenden") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
            .buttonStyle(.plain)
            .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

private struct ModeRow: View {
    let mode: Mode
    @EnvironmentObject var processor: ModeProcessor
    @EnvironmentObject var config: AppConfig

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: mode.symbolName)
                .frame(width: 22)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(mode.displayName).font(.system(.body, design: .rounded))
                Text(mode.tagline).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(shortcutString).font(.caption2).monospaced().foregroundStyle(.secondary)
            Button(buttonLabel) {
                processor.toggle(mode: mode, config: config)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(buttonColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var shortcutString: String { mode.defaultShortcutLabel }

    private var isActive: Bool { processor.activeMode == mode }

    private var buttonLabel: String {
        guard isActive else { return "Starte" }
        switch processor.status {
        case .aufnahme:                   return "Stop"
        case .transkribiert, .formuliert: return "…"
        default:                          return "Starte"
        }
    }

    private var buttonColor: Color {
        guard isActive else { return .accentColor }
        switch processor.status {
        case .aufnahme: return .red
        default:        return .accentColor
        }
    }
}
