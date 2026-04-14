import SwiftUI
import KeyboardShortcuts

struct SettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var apiKeyInput = ""
    @State private var keyStatus = ""
    @State private var selectedTab: SettingsTab = .general

    @Environment(\.openWindow) private var openWindow

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, hotkeys, prompts, vocabulary, setup, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:    return "Allgemein"
            case .hotkeys:    return "Hotkeys"
            case .prompts:    return "Prompts"
            case .vocabulary: return "Vokabular"
            case .setup:      return "Setup"
            case .about:      return "Über"
            }
        }

        var icon: String {
            switch self {
            case .general:    return "gearshape.fill"
            case .hotkeys:    return "keyboard.fill"
            case .prompts:    return "text.alignleft"
            case .vocabulary: return "character.book.closed.fill"
            case .setup:      return "checkmark.shield.fill"
            case .about:      return "info.circle.fill"
            }
        }

        var tint: Color {
            switch self {
            case .general:    return .gray
            case .hotkeys:    return .blue
            case .prompts:    return .purple
            case .vocabulary: return .green
            case .setup:      return .orange
            case .about:      return .teal
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 620, height: 480)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                TabButton(tab: tab, isSelected: selectedTab == tab) {
                    selectedTab = tab
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity)
        .background(.bar)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .general:    general
        case .hotkeys:    hotkeys
        case .prompts:    prompts
        case .vocabulary: vocabulary
        case .setup:      setup
        case .about:      about
        }
    }

    @State private var newWord = ""

    private var vocabulary: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Eigennamen & Fachbegriffe")
                .font(.headline)
            Text("Wörter, die Whisper oft falsch schreibt. Wird als Kontext mitgegeben — z.B. Namen, Marken, Fachbegriffe.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                TextField("Neues Wort oder Name", text: $newWord)
                    .onSubmit(addWord)
                Button("Hinzufügen", action: addWord)
                    .disabled(newWord.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            List {
                ForEach(Array(config.vocabulary.enumerated()), id: \.offset) { idx, word in
                    HStack {
                        Text(word)
                        Spacer()
                        Button {
                            config.vocabulary.remove(at: idx)
                            config.save()
                        } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .listStyle(.bordered)
            .frame(minHeight: 180)

            if !config.vocabulary.isEmpty {
                Text("Wird an Whisper als Prompt übergeben: \(config.vocabularyPrompt)")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .lineLimit(2)
            }
        }
        .padding()
    }

    @StateObject private var updater = Updater()

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: "bolt.fill").foregroundStyle(.yellow).font(.title)
                VStack(alignment: .leading) {
                    Text("blitzbot").font(.title2.bold())
                    Text(AppInfo.versionLabel).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            Divider()

            GroupBox("Updates") {
                VStack(alignment: .leading, spacing: 10) {
                    updaterStatusView
                    HStack {
                        Button("Jetzt prüfen") {
                            Task { await updater.checkForUpdates() }
                        }
                        .disabled(isUpdaterBusy)
                        if case .available = updater.state {
                            Button("Herunterladen") {
                                Task { await updater.download() }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        if case .ready = updater.state {
                            Button("Installieren & neu starten") {
                                updater.installAndRelaunch()
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        Spacer()
                    }
                }
                .padding(8)
            }

            GroupBox("Projekt") {
                VStack(alignment: .leading, spacing: 6) {
                    Link("GitHub-Repository", destination: AppInfo.repoURL)
                    Text("MIT-Lizenz · © 2026 blitzbot contributors")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .padding(8)
            }
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var updaterStatusView: some View {
        switch updater.state {
        case .idle:
            Text("Auf Updates prüfen").font(.caption).foregroundStyle(.secondary)
        case .checking:
            HStack { ProgressView().controlSize(.small); Text("Prüfe…").font(.caption) }
        case .upToDate:
            Label("Aktuellste Version", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green).font(.caption)
        case .available(let v, _, let notes):
            VStack(alignment: .leading, spacing: 4) {
                Label("Neue Version: \(v)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(.blue)
                if !notes.isEmpty {
                    Text(notes).font(.caption).foregroundStyle(.secondary).lineLimit(4)
                }
            }
        case .downloading(let p):
            ProgressView(value: p).frame(maxWidth: 300)
        case .ready:
            Label("Bereit zur Installation", systemImage: "arrow.triangle.2.circlepath")
                .foregroundStyle(.orange).font(.caption)
        case .error(let msg):
            Label(msg, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red).font(.caption)
        }
    }

    private var isUpdaterBusy: Bool {
        if case .checking = updater.state { return true }
        if case .downloading = updater.state { return true }
        return false
    }

    private func addWord() {
        let trimmed = newWord.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        config.vocabulary.append(trimmed)
        config.save()
        newWord = ""
    }

    private var setup: some View {
        VStack(spacing: 12) {
            Text("Berechtigungen & Installation")
                .font(.headline)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text("Öffnet den Einrichtungsdialog nochmal — falls Mikrofon, Bedienungshilfen oder Whisper-Modell fehlen.")
                .font(.caption).foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            HStack {
                Button {
                    openWindow(id: "setup")
                } label: {
                    Label("Setup öffnen", systemImage: "checkmark.shield")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            }
            Spacer()
        }
        .padding()
    }

    private var general: some View {
        Form {
            Section("Anthropic API Key") {
                HStack {
                    SecureField("sk-ant-…", text: $apiKeyInput)
                    Button("Speichern") { saveKey() }.disabled(apiKeyInput.isEmpty)
                    Button("Löschen") { deleteKey() }.disabled(!config.hasAPIKey)
                }
                HStack {
                    Image(systemName: config.hasAPIKey ? "checkmark.circle.fill" : "xmark.circle")
                        .foregroundStyle(config.hasAPIKey ? .green : .orange)
                    Text(config.hasAPIKey ? "Key in Keychain gespeichert" : "Kein Key gesetzt")
                        .font(.caption)
                    if !keyStatus.isEmpty {
                        Text(keyStatus).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Claude-Modell") {
                Picker("Modell", selection: $config.model) {
                    Text("Sonnet 4.5 (schnell, günstig)").tag("claude-sonnet-4-5")
                    Text("Opus 4.5 (höchste Qualität)").tag("claude-opus-4-5")
                    Text("Haiku 4.5 (sehr schnell)").tag("claude-haiku-4-5")
                }
                .onChange(of: config.model) { _ in config.save() }
            }
            Section("Whisper") {
                HStack {
                    Text("Binary").frame(width: 60, alignment: .leading)
                    TextField("/opt/homebrew/bin/whisper-cli", text: $config.whisperBinary)
                        .onSubmit { config.save() }
                }
                HStack {
                    Text("Modell").frame(width: 60, alignment: .leading)
                    TextField("~/.blitzbot/models/ggml-large-v3-turbo.bin",
                              text: $config.whisperModel)
                        .onSubmit { config.save() }
                }
            }
        }
        .formStyle(.grouped)
    }

    private var hotkeys: some View {
        Form {
            Section("Hotkeys — klick auf den Recorder, drück eine Kombi") {
                ForEach(Mode.allCases) { mode in
                    HStack {
                        Image(systemName: mode.symbolName).frame(width: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(mode.displayName)
                            Text(mode.tagline).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        KeyboardShortcuts.Recorder(for: mode.shortcutName)
                    }
                }
            }
            Section {
                Text("Während einer Aufnahme kannst du den Modus wechseln, indem du einen anderen Hotkey drückst — die Aufnahme läuft weiter, der Text wird dann im neuen Modus verarbeitet.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var prompts: some View {
        Form {
            ForEach(Mode.allCases) { mode in
                Section(mode.displayName) {
                    TextEditor(text: Binding(
                        get: { config.prompts[mode] ?? "" },
                        set: { config.prompts[mode] = $0; config.save() }
                    ))
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 80)
                }
            }
        }
        .formStyle(.grouped)
    }

    private func saveKey() {
        do {
            try config.setAPIKey(apiKeyInput)
            apiKeyInput = ""
            keyStatus = "Gespeichert."
        } catch {
            keyStatus = "Fehler: \(error.localizedDescription)"
        }
    }

    private func deleteKey() {
        config.removeAPIKey()
        keyStatus = "Gelöscht."
    }
}

private struct TabButton: View {
    let tab: SettingsView.SettingsTab
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(tab.tint.gradient)
                        .frame(width: 34, height: 34)
                        .shadow(color: tab.tint.opacity(0.35),
                                radius: isSelected ? 4 : 0,
                                x: 0, y: 1)
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(tab.title)
                    .font(.caption)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected
                          ? Color.primary.opacity(0.08)
                          : (hovering ? Color.primary.opacity(0.04) : .clear))
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
