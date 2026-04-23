import SwiftUI
import AppKit

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
        .onChange(of: config.llmProvider) { _ in
            processor.clearErrorIfAny()
        }
    }

    private var displayStatusLabel: String {
        if case .fehler(let msg) = processor.status,
           msg.lowercased().contains("ollama"),
           config.llmProvider != .ollama {
            return ModeProcessor.Status.bereit.label
        }
        return processor.status.label
    }

    private var header: some View {
        HStack {
            Image(systemName: "bolt.fill").foregroundStyle(.yellow)
            Text("blitzbot").font(.headline)
            Spacer()
            statusIndicator
            PrivacyToggleButton()
            Button {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "settings")
            } label: {
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
            Text(displayStatusLabel).font(.caption)
        }
    }

    private var providerKeyWarning: String? {
        switch config.llmProvider {
        case .anthropic: return config.hasAPIKey ? nil : "Kein Anthropic API-Key"
        case .openai:    return config.hasOpenAIKey ? nil : "Kein OpenAI API-Key"
        case .ollama:    return nil  // Ollama is local, no key required
        }
    }

    private var statusColor: Color {
        if case .fehler(let msg) = processor.status,
           msg.lowercased().contains("ollama"),
           config.llmProvider != .ollama {
            return .green
        }
        switch processor.status {
        case .bereit, .fertig: return .green
        case .aufnahme:        return .red
        case .transkribiert, .korrigiert, .formuliert: return .yellow
        case .fehler, .recovery: return .orange
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if let warning = providerKeyWarning {
                HStack {
                    Label(warning, systemImage: "exclamationmark.triangle")
                        .font(.caption).foregroundStyle(.orange)
                    Spacer()
                }
            }
            HStack(spacing: 12) {
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    openWindow(id: "settings")
                } label: {
                    Label("Einstellungen…", systemImage: "gearshape")
                        .font(.caption)
                }
                .keyboardShortcut(",", modifiers: .command)
                .buttonStyle(.plain)
                Spacer()
                Button("Beenden") {
                    NSApp.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: .command)
                .buttonStyle(.plain)
                .font(.caption)
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 4)
    }
}

private struct ModeRow: View {
    let mode: Mode
    @EnvironmentObject var processor: ModeProcessor
    @EnvironmentObject var config: AppConfig
    @Environment(\.openWindow) private var openWindow

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
            Button(buttonLabel) { handleTap() }
                .buttonStyle(.borderless)
                .foregroundStyle(buttonColor)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func handleTap() {
        if mode == .officeMode {
            // Route through the app delegate's toggle so the same path runs whether
            // the user used the hotkey or this button (dock-icon toggle, selection
            // capture etc. stay consistent).
            if let delegate = NSApp.delegate as? BlitzbotAppDelegate {
                delegate.toggleOfficeWindow()
            } else {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "office")
            }
        } else {
            processor.toggle(mode: mode, config: config)
        }
    }

    private var shortcutString: String { mode.defaultShortcutLabel }

    private var isActive: Bool { processor.activeMode == mode }

    private var buttonLabel: String {
        if mode == .officeMode { return "Öffnen" }
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
