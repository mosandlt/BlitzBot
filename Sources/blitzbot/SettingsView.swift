import SwiftUI
import AppKit
import KeyboardShortcuts

private enum PromptMergeMode: Hashable {
    case replace
    case append
}

struct SettingsView: View {
    @EnvironmentObject var config: AppConfig
    /// Persisted across settings open/close so the user doesn't jump back to Allgemein every time.
    @AppStorage("settings.selectedTab") private var selectedTabRaw: String = SettingsTab.general.rawValue

    @Environment(\.openWindow) private var openWindow

    @StateObject private var modelDownloader = ModelDownloader()
    @State private var showingModelDownload = false
    @State private var pendingModel: WhisperModel?

    private var selectedTab: SettingsTab {
        get { SettingsTab(rawValue: selectedTabRaw) ?? .general }
    }

    private func selectTab(_ tab: SettingsTab) { selectedTabRaw = tab.rawValue }

    enum SettingsTab: String, CaseIterable, Identifiable {
        case general, profiles, hotkeys, prompts, vocabulary, setup, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general:    return "Allgemein"
            case .profiles:   return "Profile"
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
            case .profiles:   return "person.2.fill"
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
            case .profiles:   return .indigo
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
        .frame(minWidth: 780, minHeight: 580)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private var toolbar: some View {
        HStack(spacing: 4) {
            ForEach(SettingsTab.allCases) { tab in
                TabButton(tab: tab, isSelected: selectedTab == tab) {
                    selectTab(tab)
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
        case .profiles:   ProfilesView(store: config.profileStore)
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

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            launchAtLoginEnabled = try LaunchAtLoginManager.setEnabled(enabled)
            launchAtLoginRequiresApproval = LaunchAtLoginManager.requiresApproval
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = error.localizedDescription
            Log.write("LaunchAtLogin: setEnabled(\(enabled)) failed: \(error)")
            refreshLaunchAtLoginState()
        }
    }

    private func refreshLaunchAtLoginState() {
        launchAtLoginEnabled = LaunchAtLoginManager.isEnabled
        launchAtLoginRequiresApproval = LaunchAtLoginManager.requiresApproval
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

    @State private var launchAtLoginEnabled: Bool = LaunchAtLoginManager.isEnabled
    @State private var launchAtLoginError: String?
    @State private var launchAtLoginRequiresApproval: Bool = LaunchAtLoginManager.requiresApproval

    private var general: some View {
        Form {
            Section("System") {
                Toggle(isOn: Binding(
                    get: { launchAtLoginEnabled },
                    set: { setLaunchAtLogin($0) }
                )) {
                    HStack(spacing: 6) {
                        Image(systemName: "power.circle.fill")
                            .foregroundStyle(launchAtLoginEnabled ? .green : .secondary)
                        Text("Beim Anmelden automatisch starten")
                            .fontWeight(.medium)
                    }
                }
                .onAppear { refreshLaunchAtLoginState() }
                Text("blitzbot startet beim nächsten Login automatisch und bleibt als Menüleisten-Icon oben rechts verfügbar. Kein Dock-Icon.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if launchAtLoginRequiresApproval {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("macOS wartet auf Bestätigung in Systemeinstellungen → Allgemein → Anmeldeobjekte.")
                            .font(.caption)
                        Button("Öffnen") {
                            LaunchAtLoginManager.openLoginItemsSettings()
                        }
                        .controlSize(.small)
                    }
                }
                if let err = launchAtLoginError {
                    Label(err, systemImage: "xmark.octagon.fill")
                        .foregroundStyle(.red).font(.caption)
                }
            }

            Section("LLM") {
                HStack(spacing: 8) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary)
                    Text("Provider, API-Keys und Modelle werden im Tab **Profile** verwaltet.")
                        .font(.caption)
                }
                HStack {
                    Text("Aktives Profil").frame(width: 110, alignment: .leading)
                    if let active = config.profileStore.activeProfile {
                        Text(active.name).fontWeight(.medium)
                        Text("· \(active.provider.displayName)")
                            .foregroundStyle(.secondary)
                    } else {
                        Text("Keines — Legacy-Fallback aktiv")
                            .foregroundStyle(.orange)
                    }
                    Spacer()
                    Button("Profile öffnen") { selectTab(.profiles) }
                        .controlSize(.small)
                }
            }

            Section("Privacy") {
                Toggle(isOn: $config.privacyMode) {
                    HStack(spacing: 6) {
                        Image(systemName: "lock.shield.fill")
                            .foregroundStyle(config.privacyMode ? .green : .secondary)
                        Text("Privacy Mode")
                            .fontWeight(.medium)
                    }
                }
                Text("Ausgehender Text wird lokal durchsucht (NLTagger + NSDataDetector + Regex) und erkannte Namen, Firmennamen, Orte, E-Mails, IPs, URLs und Telefonnummern werden vor dem Versand an die KI durch neutrale Platzhalter (z. B. `[NAME_1]`, `[UNTERNEHMEN_1]`) ersetzt. Die Antwort der KI wird anhand derselben Mapping-Tabelle zurückübersetzt, bevor sie bei dir landet.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Die Zuordnung lebt nur im Arbeitsspeicher und wird beim Deaktivieren sowie beim App-Beenden verworfen. Es wird nichts auf Disk geschrieben. Die Erkennung selbst läuft zu 100 % lokal über macOS-System-Frameworks — kein externer API-Call.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if config.privacyMode {
                    PrivacyEngineStatusRow(engine: config.privacyEngine)
                    PrivacyMappingInlineList(engine: config.privacyEngine)
                }
                Divider().padding(.vertical, 4)
                PrivacyCustomTermsEditor()
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
            Section("Text umschreiben (Hotkey, ohne Stimme)") {
                HStack {
                    Text("Hotkey").frame(width: 90, alignment: .leading)
                    KeyboardShortcuts.Recorder(for: .rewriteSelection)
                }
                Picker("Default-Modus", selection: $config.serviceDefaultMode) {
                    ForEach(Mode.allCases.filter { $0 != .normal && $0 != .officeMode }) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                Text("Markiere Text in einer beliebigen App, drücke den Hotkey — blitzbot liest die Auswahl, schreibt sie im Default-Modus um und fügt das Ergebnis zurück ein. Funktioniert in jeder App die Accessibility unterstützt. Als Fallback wird ⌘C simuliert und danach die Zwischenablage wiederhergestellt.")
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
                whisperModelPicker
            }
        }
        .formStyle(.grouped)
        .sheet(isPresented: $showingModelDownload) {
            ModelDownloadSheet(downloader: modelDownloader,
                               onFinish: handleModelDownloadFinish)
        }
    }

    @ViewBuilder
    private var whisperModelPicker: some View {
        let detected = WhisperModel.detect(fromPath: config.whisperModel)
        VStack(alignment: .leading, spacing: 8) {
            Picker("Modell", selection: Binding<String>(
                get: { detected?.rawValue ?? "__custom__" },
                set: { newValue in
                    if newValue == "__custom__" { return }  // selecting custom keeps the existing path
                    if let model = WhisperModel(rawValue: newValue) {
                        switchToModel(model)
                    }
                }
            )) {
                ForEach(WhisperModel.allCases) { model in
                    HStack {
                        Text(model.displayName)
                        if model.isRecommended {
                            Text("Empfohlen")
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Color.green.opacity(0.18), in: Capsule())
                                .foregroundStyle(.green)
                        }
                        Text("· \(model.sizeMB) MB")
                            .foregroundStyle(.secondary)
                    }
                    .tag(model.rawValue)
                }
                Divider()
                Text("Benutzerdefiniert (manueller Pfad)").tag("__custom__")
            }
            if let model = detected {
                Text(model.subtitle)
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                TextField("~/.blitzbot/models/<datei>.bin", text: $config.whisperModel)
                    .onSubmit { config.save() }
                Text("Manueller Pfad — kein automatischer Download oder Bereinigung.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func switchToModel(_ model: WhisperModel) {
        let alreadyOnDisk = FileManager.default.fileExists(atPath: model.localPath.path)
        if alreadyOnDisk {
            applyModelChoice(model)
            return
        }
        // Need to download first; remember the choice and open the sheet.
        pendingModel = model
        modelDownloader.setModel(model)
        showingModelDownload = true
        Task { await modelDownloader.check() }
    }

    private func applyModelChoice(_ model: WhisperModel) {
        config.whisperModel = model.localPath.path
        config.save()
        modelDownloader.setModel(model)
        let purged = modelDownloader.purgeOtherModels()
        if purged > 0 {
            Log.write("Settings: switched to \(model.rawValue), purged \(purged) old model(s)")
        }
    }

    private func handleModelDownloadFinish() {
        // Sheet was closed. If the download completed, finalize the switch.
        if case .done = modelDownloader.state, let model = pendingModel {
            applyModelChoice(model)
        }
        pendingModel = nil
        showingModelDownload = false
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
            Section("Aufnahme-Trigger") {
                Toggle("Hold-to-Talk (Hotkey gedrückt halten)", isOn: $config.holdToTalk)
                    .onChange(of: config.holdToTalk) { _ in config.save() }
                Text(config.holdToTalk
                     ? "Halte den Hotkey gedrückt während du sprichst — beim Loslassen wird transkribiert."
                     : "Drück den Hotkey einmal zum Starten, nochmal zum Stoppen (Toggle).")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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

/// Editor for the persistent "always anonymize" term list. NLTagger sometimes
/// misses short all-caps abbreviations or domain-specific code names; this list
/// lets users pin those down explicitly, case-insensitive.
///
/// List-based UX: each term is its own row with a minus button; a new-term input
/// at the bottom adds via plus button or Return.
private struct PrivacyCustomTermsEditor: View {
    @EnvironmentObject var config: AppConfig
    @State private var newTerm: String = ""
    @FocusState private var newTermFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Immer anonymisieren")
                .font(.callout.bold())
            Text("Begriffe die immer ersetzt werden — auch wenn die automatische Erkennung sie übersieht. Typisch: der Name deines Arbeitgebers, interne Projekt-Codenamen, dein Nachname. Groß-/Kleinschreibung ist egal, Wortgrenzen werden beachtet.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if config.privacyCustomTerms.isEmpty {
                Text("Noch keine Begriffe — füg unten welche hinzu.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                VStack(spacing: 3) {
                    ForEach(config.privacyCustomTerms, id: \.self) { term in
                        termRow(term)
                    }
                }
            }

            HStack(spacing: 6) {
                TextField("Neuen Begriff eingeben", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                    .focused($newTermFocused)
                    .onSubmit(addTerm)
                Button {
                    addTerm()
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                        .foregroundStyle(canAdd ? Color.accentColor : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canAdd)
                .help("Begriff hinzufügen (Return)")
            }
        }
    }

    private func termRow(_ term: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.shield.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(term)
                .font(.system(.body, design: .monospaced))
            Spacer()
            Button {
                removeTerm(term)
            } label: {
                Image(systemName: "minus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.red.opacity(0.85))
            }
            .buttonStyle(.plain)
            .help("Begriff entfernen")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.secondary.opacity(0.06))
        )
    }

    private var canAdd: Bool {
        !newTerm.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addTerm() {
        let trimmed = newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        // Case-insensitive duplicate check — keep the existing spelling if the
        // user types it again differently.
        if config.privacyCustomTerms.contains(where: {
            $0.caseInsensitiveCompare(trimmed) == .orderedSame
        }) {
            newTerm = ""
            return
        }
        var updated = config.privacyCustomTerms
        updated.append(trimmed)
        config.privacyCustomTerms = updated.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        newTerm = ""
        newTermFocused = true   // keep focus so user can add multiple in a row
    }

    private func removeTerm(_ term: String) {
        config.privacyCustomTerms.removeAll {
            $0.caseInsensitiveCompare(term) == .orderedSame
        }
    }
}

/// Live view of the current session's placeholder ↔ original mapping, inlined
/// in the Settings → Privacy section so users can see exactly what the engine
/// has anonymized so far without jumping into Office Mode's popover.
private struct PrivacyMappingInlineList: View {
    @ObservedObject var engine: PrivacyEngine

    var body: some View {
        let mappings = engine.orderedMappings()
        if !mappings.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("Anonymisierte Einträge dieser Session")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                ScrollView {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(mappings) { entry in
                            row(entry)
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
            }
        }
    }

    private func row(_ entry: PrivacyEngine.MappingEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.placeholder)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(color(for: entry.kind))
                .frame(minWidth: 120, alignment: .leading)
            Image(systemName: "arrow.left.and.right")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(entry.original)
                .font(.caption)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(color(for: entry.kind).opacity(0.08))
        )
    }

    private func color(for kind: PrivacyEngine.EntityKind) -> Color {
        switch kind {
        case .person:       return .blue
        case .organization: return .purple
        case .place:        return .teal
        case .address:      return .mint
        case .email:        return .orange
        case .ip:           return .pink
        case .url:          return .green
        case .phone:        return .indigo
        case .iban:         return .brown
        case .creditCard:   return .red
        case .mac:          return .gray
        }
    }
}

/// Live status for the Privacy session. Observes `PrivacyEngine` directly so the
/// counter and Reset button update as `anonymize(_:)` registers new entities.
private struct PrivacyEngineStatusRow: View {
    @ObservedObject var engine: PrivacyEngine

    var body: some View {
        HStack {
            Text("Aktive Session")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text("\(engine.totalEntities) Entität\(engine.totalEntities == 1 ? "" : "en")")
                .font(.caption.bold())
                .foregroundStyle(engine.totalEntities > 0 ? .green : .secondary)
            Button("Zurücksetzen") { engine.reset() }
                .controlSize(.small)
                .disabled(engine.totalEntities == 0)
        }
    }
}
