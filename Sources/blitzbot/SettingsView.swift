import SwiftUI
import AppKit
import KeyboardShortcuts

private enum PromptMergeMode: Hashable {
    case replace
    case append
}

struct SettingsView: View {
    @EnvironmentObject var config: AppConfig
    @State private var apiKeyInput = ""
    @State private var keyStatus = ""
    @State private var openaiKeyInput = ""
    @State private var openaiKeyStatus = ""
    @State private var ollamaKeyInput = ""
    @State private var ollamaKeyStatus = ""
    @State private var ollamaReachable: Bool? = nil
    @State private var ollamaAvailableModels: [String] = []
    @State private var ollamaRefreshing = false
    @State private var ollamaRefreshError: String?
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
                    NSApp.activate(ignoringOtherApps: true)
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
            Section("LLM-Provider") {
                Picker("Anbieter", selection: $config.llmProvider) {
                    ForEach(LLMProvider.allCases) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.segmented)
                Text("Wähle, wohin Business/Plus/Rage/Emoji/Prompt-Modi geschickt werden. Der Normal-Modus bleibt lokal.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Group {
                switch config.llmProvider {
                case .anthropic: anthropicSettings
                case .openai:    openaiSettings
                case .ollama:    ollamaSettings
                }
            }
            Section("Ausgabesprache / Output Language") {                Picker("Sprache", selection: $config.outputLanguage) {
                    Text("Auto (von Whisper erkannt)").tag(OutputLanguage.auto)
                    Text("Deutsch").tag(OutputLanguage.de)
                    Text("English").tag(OutputLanguage.en)
                }
                .pickerStyle(.radioGroup)
                .onChange(of: config.outputLanguage) { _ in config.save() }
                Text("Bei Auto entscheidet Whisper anhand der Aufnahme. Bei manueller Wahl wird die Transkription und Claude-Ausgabe erzwungen.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Kontextmenü (Rechtsklick → Dienste)") {
                Picker("Default-Modus", selection: $config.serviceDefaultMode) {
                    ForEach(Mode.allCases.filter { $0 != .normal }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Toggle("Bei Fehler Originaltext in Zwischenablage behalten",
                       isOn: $config.serviceClipboardFallback)
                Text("Text in beliebiger App markieren → Rechtsklick → Dienste → »blitzbot: …«. Ersetzt die Markierung mit dem umgeschriebenen Text. Der Default-Eintrag nutzt den hier gewählten Modus.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Dienste-Einstellungen öffnen") {
                        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.keyboard?Services") {
                            NSWorkspace.shared.open(url)
                        }
                    }
                    Button("Dienste-Menü neu laden") {
                        NSUpdateDynamicServices()
                    }
                }
                Text("Wenn die blitzbot-Einträge nicht erscheinen: App einmal in /Applications verschoben haben, dann »Dienste-Menü neu laden« klicken oder System abmelden/anmelden.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Section("Auto-Stop bei Inaktivität") {
                Toggle("Automatisch stoppen wenn keine Sprache erkannt wird", isOn: $config.autoStopEnabled)
                    .onChange(of: config.autoStopEnabled) { _ in config.save() }
                if config.autoStopEnabled {
                    Picker("Timeout", selection: $config.autoStopTimeout) {
                        Text("10 Sekunden").tag(TimeInterval(10))
                        Text("20 Sekunden").tag(TimeInterval(20))
                        Text("30 Sekunden").tag(TimeInterval(30))
                        Text("45 Sekunden").tag(TimeInterval(45))
                        Text("1 Minute").tag(TimeInterval(60))
                        Text("2 Minuten").tag(TimeInterval(120))
                    }
                    .onChange(of: config.autoStopTimeout) { _ in config.save() }
                    Text("Stille innerhalb eines Satzes setzt den Timer zurück, sobald du wieder sprichst.")
                        .font(.caption).foregroundStyle(.secondary)
                }
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

    @ViewBuilder
    private var anthropicSettings: some View {
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
    }

    @ViewBuilder
    private var openaiSettings: some View {
        Section("OpenAI API Key") {
            HStack {
                SecureField("sk-…", text: $openaiKeyInput)
                Button("Speichern") { saveOpenAIKey() }.disabled(openaiKeyInput.isEmpty)
                Button("Löschen") { deleteOpenAIKey() }.disabled(!config.hasOpenAIKey)
            }
            HStack {
                Image(systemName: config.hasOpenAIKey ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(config.hasOpenAIKey ? .green : .orange)
                Text(config.hasOpenAIKey ? "Key in Keychain gespeichert" : "Kein Key gesetzt")
                    .font(.caption)
                if !openaiKeyStatus.isEmpty {
                    Text(openaiKeyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        Section("OpenAI-Modell") {
            Picker("Modell", selection: $config.openaiModel) {
                Text("gpt-4o-mini (schnell, günstig)").tag("gpt-4o-mini")
                Text("gpt-4o (höchste Qualität)").tag("gpt-4o")
            }
            HStack {
                Text("oder frei").frame(width: 60, alignment: .leading)
                TextField("z.B. gpt-4o-2024-11-20", text: $config.openaiModel)
                    .textFieldStyle(.roundedBorder)
            }
            Text("Standardmäßig gpt-4o-mini. Für komplexere Umformulierungen gpt-4o.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var ollamaSettings: some View {
        Section("Ollama-Server") {
            HStack {
                Text("URL").frame(width: 60, alignment: .leading)
                TextField("http://localhost:11434", text: $config.ollamaBaseURL)
                Button {
                    Task { await refreshOllama() }
                } label: {
                    if ollamaRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(ollamaRefreshing)
            }
            HStack(spacing: 6) {
                Circle()
                    .fill(ollamaStatusColor)
                    .frame(width: 8, height: 8)
                Text(ollamaStatusText).font(.caption).foregroundStyle(.secondary)
                if let err = ollamaRefreshError, !err.isEmpty {
                    Text("— \(err)").font(.caption).foregroundStyle(.red)
                }
            }
        }
        Section("Ollama-Modell") {
            if ollamaAvailableModels.isEmpty {
                HStack {
                    TextField("llama3.2:latest", text: $config.ollamaModel)
                }
                Text("Keine Modelle gefunden. Erst „Aktualisieren“ drücken oder manuell eingeben (z.B. `llama3.2:latest`, `mistral:latest`).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Picker("Modell", selection: $config.ollamaModel) {
                    ForEach(ollamaAvailableModels, id: \.self) { name in
                        Text(name).tag(name)
                    }
                    if !ollamaAvailableModels.contains(config.ollamaModel) {
                        Text("\(config.ollamaModel) (nicht installiert)").tag(config.ollamaModel)
                    }
                }
            }
        }
        Section("Ollama API Key (optional)") {
            HStack {
                SecureField("nur bei Authentifizierung", text: $ollamaKeyInput)
                Button("Speichern") { saveOllamaKey() }.disabled(ollamaKeyInput.isEmpty)
                Button("Löschen") { deleteOllamaKey() }.disabled(!config.hasOllamaKey)
            }
            HStack {
                Image(systemName: config.hasOllamaKey ? "checkmark.circle.fill" : "minus.circle")
                    .foregroundStyle(config.hasOllamaKey ? .green : .secondary)
                Text(config.hasOllamaKey ? "Key in Keychain gespeichert" : "Kein Key nötig für lokales Ollama")
                    .font(.caption)
                if !ollamaKeyStatus.isEmpty {
                    Text(ollamaKeyStatus).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var ollamaStatusColor: Color {
        switch ollamaReachable {
        case .some(true):  return .green
        case .some(false): return .red
        case .none:        return .secondary
        }
    }

    private var ollamaStatusText: String {
        switch ollamaReachable {
        case .some(true):  return "Ollama erreichbar (\(ollamaAvailableModels.count) Modelle)"
        case .some(false): return "Ollama nicht erreichbar"
        case .none:        return "Status unbekannt — „Aktualisieren“ drücken"
        }
    }

    private func refreshOllama() async {
        ollamaRefreshing = true
        ollamaRefreshError = nil
        let client = OllamaClient(baseURL: config.ollamaBaseURL,
                                  model: config.ollamaModel,
                                  apiKey: KeychainStore.loadOllamaKey())
        let reachable = await client.healthCheck()
        ollamaReachable = reachable
        if reachable {
            do {
                let models = try await client.listModels()
                ollamaAvailableModels = models
                Log.write("Ollama: \(models.count) Modelle gefunden")
            } catch {
                ollamaAvailableModels = []
                ollamaRefreshError = error.localizedDescription
                Log.write("Ollama listModels failed: \(error.localizedDescription)")
            }
        } else {
            ollamaAvailableModels = []
        }
        ollamaRefreshing = false
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
            Section {
                Text("Leer lassen = Standard-Prompt in der gewählten Ausgabesprache. Mit eigenem Text: entweder **ersetzen** (Standard wird ignoriert) oder **anhängen** (Standard + dein Zusatz, z. B. für \"sei persönlicher\").")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(Mode.allCases) { mode in
                Section {
                    promptSectionContent(for: mode)
                } header: {
                    HStack(spacing: 6) {
                        Text(mode.displayName)
                        Spacer()
                        if let badge = promptBadge(for: mode) {
                            Text(badge.text)
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(badge.color.opacity(0.18), in: Capsule())
                                .foregroundStyle(badge.color)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private func promptSectionContent(for mode: Mode) -> some View {
        let hasCustom = (config.customPrompts[mode]?.isEmpty == false)

        if hasCustom {
            Picker("Modus", selection: Binding(
                get: { config.customPromptAppendModes[mode] == true ? PromptMergeMode.append : .replace },
                set: {
                    config.customPromptAppendModes[mode] = ($0 == .append)
                    config.save()
                }
            )) {
                Text("Standard ersetzen").tag(PromptMergeMode.replace)
                Text("An Standard anhängen").tag(PromptMergeMode.append)
            }
            .pickerStyle(.segmented)
        }

        TextEditor(text: Binding(
            get: { config.customPrompts[mode] ?? "" },
            set: {
                let trimmed = $0.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    config.customPrompts.removeValue(forKey: mode)
                    config.customPromptAppendModes.removeValue(forKey: mode)
                } else {
                    config.customPrompts[mode] = $0
                }
                config.save()
            }
        ))
        .font(.system(.body, design: .monospaced))
        .frame(minHeight: 80)

        if !hasCustom {
            Text("Standard (\(config.outputLanguage == .en ? "EN" : "DE")): \(config.displayDefaultPrompt(for: mode).prefix(160))…")
                .font(.caption2).foregroundStyle(.tertiary)
                .lineLimit(3)
        } else {
            let isAppend = config.customPromptAppendModes[mode] == true
            Text(isAppend
                 ? "Der Standard-Prompt wird vorangestellt, dein Text kommt darunter (durch Leerzeile getrennt)."
                 : "Dein Text ersetzt den Standard komplett — unabhängig von der erkannten Sprache.")
                .font(.caption2).foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Auf Standard zurücksetzen") {
                config.customPrompts.removeValue(forKey: mode)
                config.customPromptAppendModes.removeValue(forKey: mode)
                config.save()
            }
            .font(.caption)
        }
    }

    private func promptBadge(for mode: Mode) -> (text: String, color: Color)? {
        guard config.customPrompts[mode]?.isEmpty == false else { return nil }
        if config.customPromptAppendModes[mode] == true {
            return ("+ Zusatz", .blue)
        }
        return ("Override", .orange)
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

    private func saveOpenAIKey() {
        do {
            try config.setOpenAIKey(openaiKeyInput)
            openaiKeyInput = ""
            openaiKeyStatus = "Gespeichert."
        } catch {
            openaiKeyStatus = "Fehler: \(error.localizedDescription)"
        }
    }

    private func deleteOpenAIKey() {
        config.removeOpenAIKey()
        openaiKeyStatus = "Gelöscht."
    }

    private func saveOllamaKey() {
        do {
            try config.setOllamaKey(ollamaKeyInput)
            ollamaKeyInput = ""
            ollamaKeyStatus = "Gespeichert."
        } catch {
            ollamaKeyStatus = "Fehler: \(error.localizedDescription)"
        }
    }

    private func deleteOllamaKey() {
        config.removeOllamaKey()
        ollamaKeyStatus = "Gelöscht."
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
