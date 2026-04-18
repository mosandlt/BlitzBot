import SwiftUI
import AppKit
import UniformTypeIdentifiers

private enum ProfilePage: Equatable {
    case list
    case edit(ConnectionProfile, isNew: Bool)
    case discover
}

struct ProfilesView: View {
    @ObservedObject var store: ProfileStore

    @State private var page: ProfilePage = .list
    @State private var importError: String?

    var body: some View {
        switch page {
        case .list:
            ProfileListPane(
                store: store,
                importError: $importError,
                onNew: { page = .edit(ConnectionProfile(name: "Neues Profil", provider: .anthropic), isNew: true) },
                onEdit: { page = .edit($0, isNew: false) },
                onDiscover: { page = .discover },
                onImported: { importError = nil }
            )
        case .edit(let profile, let isNew):
            ProfileEditor(
                original: profile,
                isNew: isNew,
                store: store,
                onClose: { page = .list }
            )
        case .discover:
            DiscoveryPane(
                store: store,
                onClose: { page = .list }
            )
        }
    }
}

// MARK: - List pane

private struct ProfileListPane: View {
    @ObservedObject var store: ProfileStore
    @Binding var importError: String?
    let onNew: () -> Void
    let onEdit: (ConnectionProfile) -> Void
    let onDiscover: () -> Void
    let onImported: () -> Void

    /// One-time hint: on first launch after install/update, macOS may prompt for Keychain access.
    /// Explain it inline so the user knows to click "Always Allow".
    @AppStorage("profilesView.keychainHintDismissed") private var keychainHintDismissed: Bool = false

    /// Matches the user-requested accent for "active" indicators.
    static let activeColor = Color(red: 0.30, green: 0.69, blue: 0.31)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !keychainHintDismissed {
                keychainHint
            }
            if !store.profiles.isEmpty {
                quickSwitcher
            }
            Divider()
            if store.profiles.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(store.profiles) { profile in
                        row(for: profile)
                            .contentShape(Rectangle())
                            .contextMenu {
                                Button("Aktivieren") { store.setActive(profile.id) }
                                    .disabled(store.activeProfileID == profile.id)
                                Button("Bearbeiten…") { onEdit(profile) }
                                Button("Exportieren…") { exportProfile(profile) }
                                Divider()
                                Button("Löschen", role: .destructive) { store.delete(profile.id) }
                            }
                    }
                }
                .listStyle(.inset)
                .frame(maxHeight: .infinity)

                if let active = store.profiles.first(where: { $0.id == store.activeProfileID }) {
                    ActiveProfileModelsCard(
                        profile: active,
                        store: store,
                        onSelectModel: { model in selectModel(model, for: active) }
                    )
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 10)
                }
            }
            Divider()
            bottomBar
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Verbindungs-Profile").font(.title3.weight(.semibold))
                Text("Aktives Profil wird für alle LLM-Aufrufe verwendet")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if store.profiles.count > 1 {
                Text("\(store.profiles.count) Profile")
                    .font(.caption).foregroundStyle(.tertiary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.1)))
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 10)
    }

    private var keychainHint: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "key.fill")
                .foregroundStyle(.yellow)
                .font(.caption)
            VStack(alignment: .leading, spacing: 2) {
                Text("Einmalig: macOS Keychain-Zugriff").font(.caption.weight(.semibold))
                Text("Falls ein Passwort-Dialog erscheint, wähle **Immer erlauben**. Damit fragt macOS für deine API-Keys nicht mehr nach — weder beim Diktieren noch beim Öffnen dieses Tabs.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button {
                keychainHintDismissed = true
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Hinweis ausblenden")
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.yellow.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.yellow.opacity(0.25), lineWidth: 1)
        )
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
    }

    private var quickSwitcher: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(store.profiles) { profile in
                    let isActive = store.activeProfileID == profile.id
                    Button {
                        store.setActive(profile.id)
                    } label: {
                        HStack(spacing: 6) {
                            if isActive {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            Text(profile.name)
                                .font(.system(size: 13, weight: isActive ? .semibold : .medium))
                                .lineLimit(1)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(
                            Capsule(style: .continuous)
                                .fill(isActive ? Self.activeColor.opacity(0.15) : Color.secondary.opacity(0.08))
                        )
                        .overlay(
                            Capsule(style: .continuous)
                                .stroke(isActive ? Self.activeColor : Color.secondary.opacity(0.2),
                                        lineWidth: isActive ? 1.5 : 1)
                        )
                        .foregroundStyle(isActive ? Self.activeColor : Color.primary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20).padding(.bottom, 12)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("Noch keine Profile angelegt.")
                .foregroundStyle(.secondary)
            Text("„Neues Profil“, „Importieren…“ oder „Auf diesem Mac suchen“ drücken.")
                .font(.caption).foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }

    private func row(for profile: ConnectionProfile) -> some View {
        let isActive = store.activeProfileID == profile.id
        let hasSecret = store.secret(for: profile)?.isEmpty == false

        return HStack(alignment: .center, spacing: 10) {
            Button { store.setActive(profile.id) } label: {
                Image(systemName: isActive ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isActive ? Color.accentColor : .secondary)
                    .font(.system(size: 16))
            }
            .buttonStyle(.plain)
            .help(isActive ? "Aktiv" : "Als aktiv setzen")

            Image(systemName: providerIcon(profile.provider))
                .foregroundStyle(providerColor(profile.provider))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(profile.name).fontWeight(isActive ? .semibold : .regular)
                    if !hasSecret && profile.authScheme != .none {
                        Text("Kein Key")
                            .font(.caption2)
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background(Color.orange.opacity(0.18), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                }
                Text("\(profile.provider.displayName) · \(profile.baseURL)")
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button { onEdit(profile) } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)

            Button(role: .destructive) {
                store.delete(profile.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var bottomBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    onNew()
                } label: {
                    Label("Neues Profil", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)

                Button {
                    importProfile()
                } label: {
                    Label("Importieren…", systemImage: "square.and.arrow.down")
                }

                Button {
                    onDiscover()
                } label: {
                    Label("Auf diesem Mac suchen", systemImage: "magnifyingglass")
                }

                Spacer()
            }
            if let err = importError, !err.isEmpty {
                Text(err).font(.caption).foregroundStyle(.red).lineLimit(3)
            }
        }
        .padding(10)
    }

    private func importProfile() {
        importError = nil
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.title = "Profil importieren"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try Data(contentsOf: url)
                let profile = try store.importFromJSON(data)
                onImported()
                Log.write("Profile imported: \(profile.name) (\(profile.provider.rawValue))")
            } catch {
                importError = "Import: \(error.localizedDescription)"
                Log.write("Profile import failed: \(error.localizedDescription)")
            }
        }
    }

    private func exportProfile(_ profile: ConnectionProfile) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(profile.name).json"
        panel.title = "Profil exportieren (ohne Key)"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            do {
                let data = try store.exportJSON(for: profile)
                try data.write(to: url)
                Log.write("Profile exported to \(url.lastPathComponent)")
            } catch {
                importError = "Export: \(error.localizedDescription)"
            }
        }
    }

    private func selectModel(_ model: String, for profile: ConnectionProfile) {
        var updated = profile
        updated.preferredModel = model
        do {
            try store.update(updated)
            Log.write("Model switched on profile \(profile.name): \(model)")
        } catch {
            Log.write("Model switch failed: \(error.localizedDescription)")
        }
    }

    private func providerIcon(_ provider: LLMProvider) -> String {
        switch provider {
        case .anthropic:         return "cpu.fill"
        case .openai:            return "brain.head.profile"
        case .ollama:            return "macbook"
        case .appleIntelligence: return "apple.logo"
        }
    }

    private func providerColor(_ provider: LLMProvider) -> Color {
        switch provider {
        case .anthropic:         return .purple
        case .openai:            return .green
        case .ollama:            return .blue
        case .appleIntelligence: return .pink
        }
    }
}

// MARK: - Editor pane (inline, no sheet)

private struct ProfileEditor: View {
    let original: ConnectionProfile
    let isNew: Bool
    @ObservedObject var store: ProfileStore
    let onClose: () -> Void

    @State private var name: String
    @State private var provider: LLMProvider
    @State private var baseURL: String
    @State private var authScheme: AuthScheme
    @State private var sendAnthropicVersion: Bool
    @State private var preferredModel: String
    @State private var secret: String
    @State private var showSecret: Bool = false

    @State private var availableModels: [String] = []
    @State private var modelsLoading: Bool = false
    @State private var modelsError: String?
    @State private var saveError: String?

    init(original: ConnectionProfile, isNew: Bool, store: ProfileStore, onClose: @escaping () -> Void) {
        self.original = original
        self.isNew = isNew
        self.store = store
        self.onClose = onClose
        _name = State(initialValue: original.name)
        _provider = State(initialValue: original.provider)
        _baseURL = State(initialValue: original.baseURL)
        _authScheme = State(initialValue: original.authScheme)
        _sendAnthropicVersion = State(initialValue: original.sendAnthropicVersion)
        _preferredModel = State(initialValue: original.preferredModel ?? "")
        let existing = isNew ? "" : (store.secret(for: original) ?? "")
        _secret = State(initialValue: existing)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onClose()
                } label: {
                    Label("Zurück", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text(isNew ? "Neues Profil" : "Profil bearbeiten").font(.headline)
                Spacer()
                // Invisible spacer to center the title
                Label("Zurück", systemImage: "chevron.left").opacity(0).buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            Divider()

            Form {
                Section("Basis") {
                    TextField("Name", text: $name)
                    Picker("Provider", selection: $provider) {
                        ForEach(LLMProvider.allCases) { p in
                            Text(p.displayName).tag(p)
                        }
                    }
                    .onChange(of: provider) { newValue in
                        applyProviderDefaults(for: newValue)
                    }
                    if provider != .appleIntelligence {
                        TextField("Base URL", text: $baseURL)
                            .textFieldStyle(.roundedBorder)
                        Picker("Authentifizierung", selection: $authScheme) {
                            ForEach(AuthScheme.allCases) { s in
                                Text(s.displayName).tag(s)
                            }
                        }
                    }
                    if provider == .anthropic {
                        Toggle("Header `anthropic-version` mitsenden", isOn: $sendAnthropicVersion)
                    }
                    if provider == .appleIntelligence {
                        appleIntelligenceInfo
                    }
                }

                if provider != .appleIntelligence {
                    Section("Geheimnis") {
                        HStack {
                            Group {
                                if showSecret {
                                    TextField("API Key / Token", text: $secret)
                                } else {
                                    SecureField("API Key / Token", text: $secret)
                                }
                            }
                            .textFieldStyle(.roundedBorder)
                            Button {
                                showSecret.toggle()
                            } label: {
                                Image(systemName: showSecret ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.borderless)
                        }
                        if authScheme == .none {
                            Text("Ohne Authentifizierung — Feld wird beim Speichern ignoriert.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Wird nur in der macOS-Keychain gespeichert, nie als Klartext persistiert.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Modell") {
                    HStack {
                        TextField("z. B. \(defaultModelPlaceholder)", text: $preferredModel)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await refreshModels() }
                        } label: {
                            if modelsLoading {
                                ProgressView().controlSize(.small)
                            } else {
                                Label("Abrufen", systemImage: "arrow.clockwise")
                            }
                        }
                        .disabled(modelsLoading)
                    }

                    if !availableModels.isEmpty {
                        // Clean picker: only models the endpoint actually returned.
                        // No legacy "(nicht in Liste)" entry — that's surfaced as a warning below.
                        Picker("Aus Liste wählen", selection: Binding(
                            get: { availableModels.contains(preferredModel) ? preferredModel : "" },
                            set: { if !$0.isEmpty { preferredModel = $0 } }
                        )) {
                            Text("— bitte wählen —").tag("")
                            ForEach(availableModels, id: \.self) { m in
                                Text(m).tag(m)
                            }
                        }

                        if !preferredModel.isEmpty && !availableModels.contains(preferredModel) {
                            HStack(alignment: .top, spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Modell \"\(preferredModel)\" wird vom Endpoint nicht gelistet.")
                                        .font(.caption).foregroundStyle(.orange)
                                    Text("Wähle ein Modell aus der Liste oder lasse den Namen — der Request schlägt evtl. fehl.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }

                    if let err = modelsError {
                        Text(err).font(.caption).foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if availableModels.isEmpty {
                        Text("„Abrufen“ lädt die vom Endpoint unterstützten Modelle. Ohne Abruf: Modellname manuell eintippen.")
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("\(availableModels.count) Modell(e) vom Endpoint geladen.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                if let err = saveError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !isNew {
                    Button(role: .destructive) {
                        store.delete(original.id)
                        onClose()
                    } label: {
                        Label("Löschen", systemImage: "trash")
                    }
                }
                Spacer()
                Button("Abbrechen") { onClose() }
                Button(isNew ? "Anlegen" : "Speichern") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(10)
        }
    }

    private var defaultModelPlaceholder: String {
        switch provider {
        case .anthropic:         return "claude-sonnet-4-5"
        case .openai:            return "gpt-4o-mini"
        case .ollama:            return "llama3.2:latest"
        case .appleIntelligence: return AppleIntelligenceClient.modelID
        }
    }

    private func applyProviderDefaults(for newProvider: LLMProvider) {
        let oldDefaults = ConnectionProfile.defaultBaseURL(for: original.provider)
        if baseURL == oldDefaults || baseURL.isEmpty {
            baseURL = ConnectionProfile.defaultBaseURL(for: newProvider)
        }
        authScheme = ConnectionProfile.defaultAuthScheme(for: newProvider)
        sendAnthropicVersion = (newProvider == .anthropic)
        availableModels = []
        modelsError = nil
    }

    private func refreshModels() async {
        modelsLoading = true
        modelsError = nil
        defer { modelsLoading = false }

        let draft = buildProfile()
        let secretForFetch: String? = (authScheme == .none) ? nil : secret
        do {
            let models = try await ModelDiscovery.list(profile: draft, secret: secretForFetch)
            availableModels = models
            if models.isEmpty {
                modelsError = "Endpoint gab eine leere Liste zurück."
            }
            Log.write("Profile \(draft.provider.rawValue): \(models.count) Modelle vom Endpoint")
        } catch {
            availableModels = []
            modelsError = error.localizedDescription
            Log.write("Model discovery failed (\(draft.provider.rawValue)): \(error.localizedDescription)")
        }
    }

    private func buildProfile() -> ConnectionProfile {
        var p = original
        p.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        p.provider = provider
        p.baseURL = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        p.authScheme = authScheme
        p.sendAnthropicVersion = sendAnthropicVersion
        let trimmedModel = preferredModel.trimmingCharacters(in: .whitespacesAndNewlines)
        p.preferredModel = trimmedModel.isEmpty ? nil : trimmedModel
        return p
    }

    private func save() {
        let profile = buildProfile()
        do {
            if isNew {
                try store.add(profile, secret: authScheme == .none ? nil : secret)
                Log.write("Profile created: \(profile.name) (\(profile.provider.rawValue))")
            } else {
                let trimmedSecret = secret.trimmingCharacters(in: .whitespaces)
                try store.update(profile,
                                 secret: (authScheme == .none || trimmedSecret.isEmpty) ? nil : secret,
                                 clearSecret: authScheme != .none && trimmedSecret.isEmpty)
                Log.write("Profile updated: \(profile.name)")
            }
            onClose()
        } catch {
            saveError = error.localizedDescription
            Log.write("Profile save failed: \(error.localizedDescription)")
        }
    }

    /// Info panel shown in the editor when Provider = Apple Intelligence.
    /// Explains the on-device nature and — on macOS 26+ — the live
    /// `SystemLanguageModel.default.availability` status.
    @ViewBuilder private var appleIntelligenceInfo: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("On-device — kein Netzwerk, kein Key, kein Cost pro Call.",
                  systemImage: "apple.logo")
                .font(.caption)
            Text("Läuft ausschließlich auf deinem Mac über Apple Intelligence (FoundationModels-Framework). Modellqualität ~3B-Klasse — stark für Rewrites und Ton-Wechsel, schwächer als Claude/GPT für kreatives Prompt-Generieren.")
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            appleIntelligenceAvailabilityBadge
        }
    }

    @ViewBuilder private var appleIntelligenceAvailabilityBadge: some View {
        HStack(spacing: 6) {
            Image(systemName: appleIntelligenceStatus.icon)
                .foregroundStyle(appleIntelligenceStatus.color)
            Text(appleIntelligenceStatus.label)
                .font(.caption)
                .foregroundStyle(appleIntelligenceStatus.color)
        }
    }

    private var appleIntelligenceStatus: (icon: String, label: String, color: Color) {
        if #available(macOS 26.0, *) {
            #if canImport(FoundationModels)
            return appleIntelligenceLiveStatus()
            #else
            return ("exclamationmark.triangle.fill",
                    "Build ohne Apple-Intelligence-Support",
                    .orange)
            #endif
        } else {
            return ("exclamationmark.triangle.fill",
                    "Erfordert macOS 26 oder neuer — aktuelles System ist zu alt.",
                    .orange)
        }
    }
}

// MARK: - Apple Intelligence live availability probe (split out of the ViewBuilder
// so the @available attribute can be applied cleanly).
#if canImport(FoundationModels)
import FoundationModels

@available(macOS 26.0, *)
private func appleIntelligenceLiveStatus() -> (icon: String, label: String, color: Color) {
    switch SystemLanguageModel.default.availability {
    case .available:
        return ("checkmark.seal.fill", "Verfügbar auf diesem Mac.", .green)
    case .unavailable(let reason):
        let text: String
        switch reason {
        case .deviceNotEligible:
            text = "Gerät nicht kompatibel (Apple Silicon + genug RAM nötig)."
        case .appleIntelligenceNotEnabled:
            text = "Apple Intelligence in Systemeinstellungen aktivieren."
        case .modelNotReady:
            text = "Modell lädt noch im Hintergrund."
        @unknown default:
            text = "Nicht verfügbar (unbekannter Grund)."
        }
        return ("exclamationmark.triangle.fill", text, .orange)
    @unknown default:
        return ("questionmark.circle.fill", "Unbekannter Status.", .secondary)
    }
}
#endif

// MARK: - Discovery pane

private struct DiscoveryPane: View {
    @ObservedObject var store: ProfileStore
    let onClose: () -> Void

    @State private var candidates: [DiscoveredProfile] = []
    @State private var selectedIDs: Set<UUID> = []
    @State private var scanned: Bool = false
    @State private var info: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button { onClose() } label: {
                    Label("Zurück", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                Spacer()
                Text("Auf diesem Mac suchen").font(.headline)
                Spacer()
                Label("Zurück", systemImage: "chevron.left").opacity(0).buttonStyle(.borderless)
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Durchsuchte Pfade (nur lesen, nichts wird übertragen):")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(ProfileScanner.inspectedRelativePaths, id: \.self) { p in
                    Text("~/\(p)").font(.caption.monospaced()).foregroundStyle(.tertiary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider()

            if !scanned {
                Spacer()
                Button {
                    runScan()
                } label: {
                    Label("Jetzt scannen", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
                Spacer()
            } else if candidates.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 32)).foregroundStyle(.secondary)
                    Text("Keine kompatiblen Configs gefunden.")
                        .foregroundStyle(.secondary)
                    Button("Erneut scannen") { runScan() }.font(.caption)
                    Spacer()
                }
                .frame(maxWidth: .infinity)
            } else {
                List {
                    ForEach(candidates) { cand in
                        Button {
                            toggle(cand.id)
                        } label: {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: selectedIDs.contains(cand.id)
                                      ? "checkmark.square.fill" : "square")
                                    .foregroundStyle(selectedIDs.contains(cand.id) ? Color.accentColor : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(cand.suggestedName).fontWeight(.medium)
                                        Text(cand.provider.displayName)
                                            .font(.caption).foregroundStyle(.secondary)
                                        if cand.secret != nil {
                                            Text("mit Key")
                                                .font(.caption2)
                                                .padding(.horizontal, 5).padding(.vertical, 1)
                                                .background(Color.green.opacity(0.18), in: Capsule())
                                                .foregroundStyle(.green)
                                        }
                                    }
                                    Text(cand.baseURL)
                                        .font(.caption.monospaced()).foregroundStyle(.secondary)
                                        .lineLimit(1).truncationMode(.middle)
                                    Text("Quelle: \(abbreviatedPath(cand.sourcePath))")
                                        .font(.caption2).foregroundStyle(.tertiary)
                                        .lineLimit(1).truncationMode(.middle)
                                }
                            }
                            .padding(.vertical, 3)
                        }
                        .buttonStyle(.plain)
                        .contentShape(Rectangle())
                    }
                }
                .listStyle(.inset)
            }

            Divider()
            HStack {
                if let info {
                    Text(info).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if scanned {
                    Button("Erneut scannen") { runScan() }
                }
                Button("Ausgewählte importieren") {
                    importSelected()
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedIDs.isEmpty)
            }
            .padding(10)
        }
    }

    private func runScan() {
        info = nil
        candidates = ProfileScanner.scan()
        // Auto-select everything found; user can uncheck.
        selectedIDs = Set(candidates.map { $0.id })
        scanned = true
        Log.write("Profile scan: \(candidates.count) candidate(s)")
    }

    private func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) }
        else { selectedIDs.insert(id) }
    }

    private func importSelected() {
        var ok = 0
        var failed = 0
        for cand in candidates where selectedIDs.contains(cand.id) {
            do {
                try store.add(cand.makeProfile(), secret: cand.secret)
                ok += 1
            } catch {
                failed += 1
                Log.write("Import candidate failed: \(error.localizedDescription)")
            }
        }
        info = "\(ok) importiert, \(failed) fehlgeschlagen."
        if failed == 0 { onClose() }
    }

    private func abbreviatedPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Active-profile models card

private struct ActiveProfileModelsCard: View {
    let profile: ConnectionProfile
    @ObservedObject var store: ProfileStore
    let onSelectModel: (String) -> Void

    private let activeColor = Color(red: 0.30, green: 0.69, blue: 0.31)

    @State private var models: [String] = []
    @State private var loading: Bool = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 8) {
                Image(systemName: "cpu")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 14))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Modelle beim aktiven Profil").font(.system(size: 13, weight: .semibold))
                    HStack(spacing: 4) {
                        Text(profile.name).font(.caption).foregroundStyle(.secondary)
                        if !models.isEmpty {
                            Text("· \(models.count) verfügbar").font(.caption).foregroundStyle(.tertiary)
                        }
                        if let pref = profile.preferredModel, !pref.isEmpty {
                            Text("· \(pref)")
                                .font(.caption.monospaced())
                                .foregroundStyle(activeColor)
                                .lineLimit(1).truncationMode(.middle)
                        } else {
                            Text("· kein Modell gewählt")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                Spacer()
                Button {
                    Task { await fetch() }
                } label: {
                    if loading {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise").font(.system(size: 13))
                    }
                }
                .buttonStyle(.borderless)
                .disabled(loading)
                .help("Modelle neu laden")
            }

            // Model grid
            if loading && models.isEmpty {
                Text("Lädt…").font(.caption).foregroundStyle(.secondary)
            } else if let error {
                Text(error).font(.caption).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            } else if models.isEmpty {
                Text("Noch nicht geladen — Refresh drücken.")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), alignment: .leading),
                        GridItem(.flexible(), alignment: .leading)
                    ],
                    spacing: 4
                ) {
                    ForEach(models, id: \.self) { name in
                        Button { onSelectModel(name) } label: {
                            HStack(spacing: 5) {
                                Image(systemName: isActive(name) ? "checkmark.circle.fill" : "circle")
                                    .font(.caption)
                                    .foregroundStyle(isActive(name) ? activeColor : Color.secondary.opacity(0.45))
                                Text(name)
                                    .font(.caption.monospaced())
                                    .lineLimit(1).truncationMode(.middle)
                                    .fontWeight(isActive(name) ? .semibold : .regular)
                                    .foregroundStyle(isActive(name) ? activeColor : Color.primary)
                                Spacer(minLength: 0)
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(isActive(name) ? activeColor.opacity(0.12) : Color.clear)
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
        .task(id: profile.id) {
            models = []
            error = nil
            await fetch()
        }
    }

    private func isActive(_ model: String) -> Bool { profile.preferredModel == model }

    private func fetch() async {
        loading = true
        error = nil
        let fetchingID = profile.id
        defer { loading = false }
        do {
            let secret = store.secret(for: profile)
            let list = try await ModelDiscovery.list(profile: profile, secret: secret)
            guard fetchingID == profile.id else { return }
            models = list
        } catch {
            guard fetchingID == profile.id else { return }
            self.error = error.localizedDescription
            models = []
        }
    }
}