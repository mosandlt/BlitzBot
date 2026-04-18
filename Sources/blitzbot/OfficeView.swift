import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Office Mode window — an interactive selection-rewriter with preview + mode picker.
///
/// Flow:
///   1. User presses `⌘⌥O`. The hotkey handler in `BlitzbotAppDelegate.toggleOfficeWindow`
///      grabs the selection from the currently focused app *before* blitzbot steals focus,
///      remembers the source app's bundle ID, and stores both in `config.pendingOfficeContent`.
///   2. The window opens; `.onAppear` pulls the pending content, pre-fills the editor, and
///      displays the source-app name as a chip.
///   3. User can tweak the text, optionally drop a file to replace it, and picks a mode.
///   4. `⌘↵` / "Verarbeiten" → routes the text through `LLMRouter` with the picked mode's
///      system prompt. Result shows in the preview panel and is auto-copied to the clipboard.
///   5. `⌘↵` / "In App einfügen" → closes the window, re-activates the source app (by bundle
///      ID), and simulates ⌘V via `Paster`.
///
/// Privacy: no persistence. Input / output live only in `@State`. The result goes to the
/// pasteboard (user's own surface) and optionally into their source app. Nothing is logged
/// beyond lengths.
struct OfficeView: View {
    @EnvironmentObject var config: AppConfig

    @State private var inputText: String = ""
    @State private var outputText: String = ""
    @State private var selectedMode: Mode = .business
    @State private var sourceLabel: String = ""
    @State private var sourceAppBundleID: String?
    @State private var droppedFilename: String?
    @State private var isDropTargeted = false
    @State private var isProcessing = false
    @State private var errorMessage: String?
    @State private var copyFeedback = false
    @State private var pasteFeedback = false
    @State private var hasPrefilled = false
    /// Profile chosen for this Office session. Nil = fall back to legacy provider.
    /// Does NOT mutate `config.profileStore.activeProfileID` — the global active
    /// profile stays put, this is a per-session override.
    @State private var selectedProfileID: UUID?
    /// Model override for the current session. Empty = use the profile's `preferredModel`.
    @State private var modelOverride: String = ""
    /// Models fetched from the current profile's endpoint. Reset on profile switch.
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var modelFetchError: String?

    private static let maxFileSize = 200 * 1024
    private static let allowedExtensions: Set<String> = [
        "txt", "md", "markdown", "rst",
        "json", "csv", "tsv", "log",
        "swift", "py", "js", "ts", "tsx", "jsx", "mjs",
        "html", "htm", "xml", "yaml", "yml", "toml", "ini", "conf",
        "sh", "bash", "zsh", "fish",
        "rb", "go", "rs", "java", "kt", "c", "cpp", "h", "hpp", "cs", "php",
        "sql", "plist", "env", "tex"
    ]

    /// Mode picker options — Normal is a no-op (empty prompt) so we hide it, and
    /// Office is redundant inside its own window (the "Office" mode is just a marker
    /// for the window path, not something you'd pick *inside* the window).
    private var pickerModes: [Mode] {
        Mode.allCases.filter { $0 != .normal && $0 != .officeMode }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            Divider()
            sourceChip
            editor
            dropzone
            modePicker
            actionRow
            if let err = errorMessage { errorBanner(err) }
            outputSection
        }
        .padding(20)
        .frame(minWidth: 600, minHeight: 640)
        .onAppear {
            prefillIfFresh()
            // Default mode = the service-default (same one ⌘⌥0 uses). Guard against
            // a stale value pointing at a mode we hide in this picker.
            var initial = config.serviceDefaultMode
            if !pickerModes.contains(initial) { initial = .business }
            selectedMode = initial
            Log.write("Office: view appeared (profile=\(selectedProfile?.name ?? "legacy") mode=\(initial.rawValue) chars=\(inputText.count))")
            // Ask the delegate to flip activation policy to .regular so the Dock
            // icon is visible. Covers hotkey toggle, menu-bar open, and SwiftUI
            // auto-restore — the delegate de-dupes internally.
            (NSApp.delegate as? BlitzbotAppDelegate)?.ensureOfficePolicyActive()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.yellow)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Office").font(.title3.bold())
                    Text("Auswahl holen · Modus wählen · zurückfügen")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            profileAndModelRow
        }
    }

    private var profileAndModelRow: some View {
        HStack(spacing: 10) {
            profileMenu
            modelMenu
            Spacer()
            PrivacyToggleButton()
                .environmentObject(config)
                .environmentObject(config.privacyEngine)
        }
    }

    private var profileMenu: some View {
        Menu {
            if config.profileStore.profiles.isEmpty {
                Text("Keine Profile konfiguriert")
            } else {
                ForEach(config.profileStore.profiles) { profile in
                    Button {
                        switchProfile(to: profile)
                    } label: {
                        if profile.id == selectedProfileID {
                            Label(profile.name, systemImage: "checkmark")
                        } else {
                            Text(profile.name)
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "person.crop.rectangle.stack")
                    .font(.caption)
                Text(profileMenuLabel)
                    .font(.caption.bold())
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.12))
            )
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isProcessing || config.profileStore.profiles.isEmpty)
    }

    private var profileMenuLabel: String {
        if let profile = selectedProfile { return profile.name }
        if config.profileStore.profiles.isEmpty {
            return "\(config.llmProvider.displayName) (Legacy)"
        }
        return "Kein Profil"
    }

    private var modelPlaceholder: String {
        selectedProfile?.preferredModel
            ?? defaultModelHint(for: selectedProfile?.provider ?? config.llmProvider)
    }

    private var effectiveModel: String {
        let trimmed = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return selectedProfile?.preferredModel ?? modelPlaceholder
    }

    /// Dropdown that lists models fetched via `ModelDiscovery`. First open triggers
    /// the fetch lazily; profile switches clear the cache. Keeps a "Standard des
    /// Profils" reset entry so users can quickly fall back.
    private var modelMenu: some View {
        Menu {
            if isFetchingModels {
                Label("Lade Modelle…", systemImage: "arrow.triangle.2.circlepath")
                    .disabled(true)
            } else if let err = modelFetchError {
                Text("Fehler: \(err)").foregroundStyle(.red)
                Button("Erneut versuchen") { Task { await fetchModelsAsync() } }
            } else if availableModels.isEmpty {
                Button {
                    Task { await fetchModelsAsync() }
                } label: {
                    Label("Modelle abrufen", systemImage: "arrow.down.circle")
                }
            } else {
                ForEach(availableModels, id: \.self) { model in
                    Button {
                        modelOverride = model
                        outputText = ""
                        Log.write("Office: model picked=\(model)")
                    } label: {
                        if model == effectiveModel {
                            Label(model, systemImage: "checkmark")
                        } else {
                            Text(model)
                        }
                    }
                }
                Divider()
                if let profileDefault = selectedProfile?.preferredModel, !profileDefault.isEmpty {
                    Button {
                        modelOverride = ""
                        outputText = ""
                    } label: {
                        Label("Profil-Standard: \(profileDefault)", systemImage: "arrow.uturn.backward")
                    }
                }
                Button("Liste neu laden") { Task { await fetchModelsAsync() } }
            }
        } label: {
            HStack(spacing: 5) {
                if isFetchingModels {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "cpu")
                        .font(.caption)
                }
                Text(effectiveModel.isEmpty ? "Modell wählen" : effectiveModel)
                    .font(.system(.caption, design: .monospaced).bold())
                    .lineLimit(1)
                    .truncationMode(.middle)
                Image(systemName: "chevron.down")
                    .font(.caption2)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.secondary.opacity(0.12))
            )
            .foregroundStyle(.primary)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(isProcessing || selectedProfile == nil)
        .help("Modell für diese Session. Klicken um die Liste vom Endpoint zu laden.")
    }

    private func fetchModelsAsync() async {
        guard let profile = selectedProfile else { return }
        isFetchingModels = true
        modelFetchError = nil
        defer { isFetchingModels = false }
        let secret = config.profileStore.secret(for: profile)
        do {
            let models = try await ModelDiscovery.list(profile: profile, secret: secret)
            availableModels = models
            Log.write("Office: fetched \(models.count) models for \(profile.name)")
        } catch {
            modelFetchError = error.localizedDescription
            Log.write("Office: model fetch FAILED — \(error.localizedDescription)")
        }
    }

    private var selectedProfile: ConnectionProfile? {
        guard let id = selectedProfileID else { return nil }
        return config.profileStore.profiles.first { $0.id == id }
    }

    private func switchProfile(to profile: ConnectionProfile) {
        selectedProfileID = profile.id
        modelOverride = profile.preferredModel ?? ""
        availableModels = []
        modelFetchError = nil
        outputText = ""  // result from a different profile is stale; re-run
        Log.write("Office: switched to profile \"\(profile.name)\" (\(profile.provider.rawValue))")
    }

    private func defaultModelHint(for provider: LLMProvider) -> String {
        switch provider {
        case .anthropic:         return "claude-sonnet-4-5"
        case .openai:            return "gpt-4o-mini"
        case .ollama:            return "llama3.2:latest"
        case .appleIntelligence: return AppleIntelligenceClient.modelID
        }
    }

    // MARK: - Source chip

    @ViewBuilder
    private var sourceChip: some View {
        if !sourceLabel.isEmpty {
            HStack(spacing: 6) {
                Image(systemName: "arrow.up.doc")
                    .font(.caption2)
                Text("Quelle: \(sourceLabel)")
                    .font(.caption)
                Spacer()
                Button("Leeren") {
                    inputText = ""
                    outputText = ""
                    droppedFilename = nil
                    sourceLabel = ""
                    sourceAppBundleID = nil
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.accentColor.opacity(0.1))
            )
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Editor

    private var editor: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Text").font(.callout.bold())
                Spacer()
                Text("\(inputText.count) Zeichen")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            TextEditor(text: $inputText)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 140, maxHeight: 200)
                .padding(4)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.4))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.25), lineWidth: 1)
                )
                .disabled(isProcessing)
        }
    }

    // MARK: - Dropzone

    private var dropzone: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    isDropTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 1.2, dash: [4, 4])
                )
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(isDropTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
                )
            HStack(spacing: 6) {
                Image(systemName: droppedFilename != nil ? "doc.text.fill" : "arrow.down.doc")
                    .font(.callout)
                    .foregroundStyle(droppedFilename != nil ? Color.accentColor : .secondary)
                if let name = droppedFilename {
                    Text(name).font(.caption).lineLimit(1).truncationMode(.middle)
                } else {
                    Text("Optional: Datei ablegen (txt · md · json · csv · code · max 200 KB)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
        }
        .frame(height: 40)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    // MARK: - Mode picker

    private var modePicker: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Modus").font(.callout.bold())
            HStack(spacing: 6) {
                ForEach(pickerModes) { mode in
                    OfficeModePill(
                        mode: mode,
                        isActive: selectedMode == mode,
                        disabled: isProcessing,
                        action: { selectedMode = mode }
                    )
                }
            }
        }
    }

    // MARK: - Action row

    private var actionRow: some View {
        HStack(spacing: 10) {
            if isProcessing {
                ProgressView().controlSize(.small)
                Text("Verarbeite…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Primary action depends on state: process first, then paste-back.
            // Whichever button currently carries ⌘↵ is the one Return-equivalent fires.
            if outputText.isEmpty {
                Button {
                    Log.write("Office: Verarbeiten button tapped (mode=\(selectedMode.rawValue) inputLen=\(inputText.count))")
                    Task { await process() }
                } label: {
                    Label("Verarbeiten", systemImage: "sparkles")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isProcessing || trimmedInput.isEmpty)
            } else {
                Button {
                    Log.write("Office: re-process button tapped (mode=\(selectedMode.rawValue))")
                    Task { await process() }
                } label: {
                    Label("Neu verarbeiten", systemImage: "arrow.clockwise")
                }
                .disabled(isProcessing || trimmedInput.isEmpty)

                Button {
                    Log.write("Office: Einfügen button tapped (outLen=\(outputText.count) sourceApp=\(sourceAppBundleID ?? "nil"))")
                    pasteBack()
                } label: {
                    Label("In App einfügen", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(isProcessing)
            }
        }
    }

    // MARK: - Error banner

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button("Verwerfen") { errorMessage = nil }
                .buttonStyle(.borderless)
                .font(.caption)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.orange.opacity(0.12))
        )
    }

    // MARK: - Output section

    @ViewBuilder
    private var outputSection: some View {
        if !outputText.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Ergebnis").font(.callout.bold())
                    Spacer()
                    if copyFeedback {
                        Text("Kopiert ✓").font(.caption).foregroundStyle(.green)
                    }
                    if pasteFeedback {
                        Text("Eingefügt ✓").font(.caption).foregroundStyle(.green)
                    }
                    Button {
                        copyOnly()
                    } label: {
                        Label("In Zwischenablage", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
                ScrollView {
                    Text(outputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(minHeight: 120, maxHeight: 260)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color(NSColor.textBackgroundColor).opacity(0.35))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color.secondary.opacity(0.2), lineWidth: 1)
                )
            }
        }
    }

    // MARK: - Pre-fill

    private func prefillIfFresh() {
        guard !hasPrefilled else { return }
        hasPrefilled = true

        if let pending = config.pendingOfficeContent,
           Date().timeIntervalSince(pending.createdAt) < 10 {
            sourceAppBundleID = pending.sourceAppBundleID
            if !pending.text.isEmpty {
                inputText = pending.text
                sourceLabel = pending.sourceAppBundleID.flatMap(appDisplayName) ?? "Markierter Text"
            } else if let clip = clipboardText(), !clip.isEmpty {
                inputText = clip
                sourceLabel = "Zwischenablage"
            }
            config.pendingOfficeContent = nil
        } else if let clip = clipboardText(), !clip.isEmpty {
            // Window opened via menu bar (no hotkey → no pending content), fall
            // back to whatever is currently on the clipboard.
            inputText = clip
            sourceLabel = "Zwischenablage"
        }

        // Seed profile + model from the currently active profile so defaults just work.
        if selectedProfileID == nil, let active = config.profileStore.activeProfile {
            selectedProfileID = active.id
            if modelOverride.isEmpty {
                modelOverride = active.preferredModel ?? ""
            }
        }
    }

    private func clipboardText() -> String? {
        guard let s = NSPasteboard.general.string(forType: .string), !s.isEmpty else { return nil }
        guard s.count <= Self.maxFileSize else { return nil }
        return s
    }

    private func appDisplayName(from bundleID: String) -> String? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return bundleID
        }
        return FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard let provider = providers.first else { return false }
        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { item, _ in
            var url: URL?
            if let u = item as? URL { url = u }
            else if let data = item as? Data {
                url = URL(dataRepresentation: data, relativeTo: nil)
            } else if let s = item as? String {
                url = URL(string: s)
            }
            guard let url else { return }
            Task { @MainActor in await loadFile(url) }
        }
        return true
    }

    private func loadFile(_ url: URL) async {
        errorMessage = nil
        let ext = url.pathExtension.lowercased()
        guard Self.allowedExtensions.contains(ext) else {
            errorMessage = "Dateityp .\(ext) nicht unterstützt (nur Text-basierte Dateien)"
            return
        }
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let size = (attrs?[.size] as? Int) ?? 0
        guard size > 0 else {
            errorMessage = "Datei ist leer"
            return
        }
        guard size <= Self.maxFileSize else {
            errorMessage = "Datei zu groß (\(size / 1024) KB, max 200 KB)"
            return
        }
        let content: String
        if let utf8 = try? String(contentsOf: url, encoding: .utf8) {
            content = utf8
        } else if let latin = try? String(contentsOf: url, encoding: .isoLatin1) {
            content = latin
        } else {
            errorMessage = "Datei enthält keine lesbaren Zeichen (binär?)"
            return
        }
        inputText = content
        droppedFilename = url.lastPathComponent
        sourceLabel = "Datei: \(url.lastPathComponent)"
        sourceAppBundleID = nil // File-origin input has no source app to paste back to.
        outputText = ""
        Log.write("Office: loaded file \(url.lastPathComponent) (\(content.count) chars)")
    }

    // MARK: - Process

    private var trimmedInput: String {
        inputText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func process() async {
        let text = trimmedInput
        guard !text.isEmpty else {
            Log.write("Office: process aborted — empty input")
            return
        }
        errorMessage = nil
        outputText = ""
        copyFeedback = false
        pasteFeedback = false
        isProcessing = true
        defer { isProcessing = false }

        let language = detectLanguage(text)
        let rawPrompt = config.prompt(for: selectedMode, language: language)
        // Defensive: if the resolved prompt is empty (user saved an empty override,
        // or selectedMode is somehow Normal which is no-op) fall back to the mode's
        // built-in default — otherwise the client would just echo the input.
        let systemPrompt = rawPrompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? selectedMode.defaultSystemPrompt(for: language)
            : rawPrompt
        let preview = systemPrompt.prefix(60).replacingOccurrences(of: "\n", with: " ")
        Log.write("Office: process start mode=\(selectedMode.rawValue) chars=\(text.count) lang=\(language) promptLen=\(systemPrompt.count) preview=\"\(preview)\"")

        // If the effective prompt is still empty (Normal mode that got through somehow),
        // treat as pass-through — output = input.
        guard !systemPrompt.isEmpty else {
            outputText = text
            autoCopyResult()
            Log.write("Office: pass-through (empty prompt)")
            return
        }

        do {
            let output: String
            if let base = selectedProfile {
                // Honor the user's per-session profile + model override. Copy-and-mutate
                // the struct — `keychainAccount` is derived from `id`, which stays,
                // so the profile's stored secret is still found.
                var override = base
                let trimmedModel = modelOverride.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmedModel.isEmpty { override.preferredModel = trimmedModel }
                Log.write("Office: using profile \"\(override.name)\" model=\(override.preferredModel ?? "default")")
                output = try await LLMRouter.rewrite(text: text,
                                                     systemPrompt: systemPrompt,
                                                     config: config,
                                                     profileOverride: override)
            } else {
                // No profile selected (user has none configured) — legacy fallback.
                output = try await LLMRouter.rewrite(text: text,
                                                     systemPrompt: systemPrompt,
                                                     config: config)
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                errorMessage = "Leeres Ergebnis — prüfe API-Key oder Modell-Verfügbarkeit"
                Log.write("Office: process FAILED — empty LLM output")
                return
            }
            outputText = trimmed
            autoCopyResult()
            Log.write("Office: process ok out=\(trimmed.count)")
        } catch {
            let providerLabel = selectedProfile?.name
                ?? config.profileStore.activeProfile?.name
                ?? config.llmProvider.displayName
            let llmErr = LLMError.classify(error, provider: providerLabel)
            Log.write("Office: process FAILED — \(llmErr.errorDescription ?? "unknown")")
            errorMessage = llmErr.errorDescription ?? error.localizedDescription
        }
    }

    private func autoCopyResult() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(outputText, forType: .string)
    }

    private func copyOnly() {
        autoCopyResult()
        copyFeedback = true
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            copyFeedback = false
        }
    }

    // MARK: - Paste back

    private func pasteBack() {
        let payload = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !payload.isEmpty else { return }

        // Put result on the clipboard first (it's already there from autoCopyResult, but be safe).
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)

        // Close the Office window so focus can leave blitzbot.
        if let window = NSApp.windows.first(where: { $0.title == "blitzbot Office" }) {
            window.close()
        }

        // Re-activate source app (if we know it) and simulate ⌘V.
        if let bundleID = sourceAppBundleID,
           let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == bundleID }) {
            app.activate(options: [])
            Log.write("Office: paste-back → \(bundleID)")
            // Small delay so the source app regains focus before the paste event fires.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
                Paster.pasteText(payload, autoReturn: false)
            }
        } else {
            // Unknown source (file-drop input, or app gone) — result stays on
            // the clipboard so the user can paste it manually wherever they want.
            Log.write("Office: paste-back skipped — no source app; result stays in clipboard")
            pasteFeedback = true
        }
    }

    /// Same stop-word ratio heuristic as `ModeProcessor.detectLanguageFromContent`,
    /// duplicated here so Office doesn't depend on the voice pipeline.
    private func detectLanguage(_ text: String) -> String {
        let tokens = text.lowercased()
            .split { $0.isWhitespace || $0.isPunctuation }
            .map(String.init)
        guard tokens.count >= 3 else { return "de" }
        let en: Set<String> = ["the","is","a","to","of","and","in","that","it","for","with",
                               "on","this","be","are","from","as","at","by","an","or","not",
                               "have","has","was","were","will","can","would","could","should"]
        let de: Set<String> = ["der","die","das","und","ist","ich","ein","eine","nicht","mit",
                               "von","den","zu","auf","dass","für","sich","als","im","wir",
                               "habe","werden","haben","war","wird","kann","auch","bei"]
        var enHits = 0, deHits = 0
        for t in tokens {
            if en.contains(t) { enHits += 1 }
            if de.contains(t) { deHits += 1 }
        }
        return enHits > deHits ? "en" : "de"
    }
}

/// Shared shield-style privacy toggle. Used in both the Office window header and
/// the recording HUD.
///
/// `compact = true` (HUD): a single click toggles the mode directly. No popover —
/// we're on a nonactivating panel and popovers would steal focus.
///
/// `compact = false` (Office): a click opens a popover that shows the current
/// mapping (`placeholder ↔ original`) + an inline toggle + reset. Gives the user
/// visibility into what's been anonymized so far.
struct PrivacyToggleButton: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var engine: PrivacyEngine
    var compact: Bool = false
    @State private var showPopover = false

    var body: some View {
        Button {
            if compact {
                config.privacyMode.toggle()
            } else {
                showPopover.toggle()
            }
        } label: {
            pillLabel
        }
        .buttonStyle(.plain)
        .help(helpText)
        .popover(isPresented: $showPopover, arrowEdge: .top) {
            PrivacyDetailsPopover()
                .environmentObject(config)
                .environmentObject(engine)
        }
    }

    private var pillLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: config.privacyMode ? "lock.shield.fill" : "lock.shield")
                .font(.caption)
                .foregroundStyle(config.privacyMode ? Color.green : foregroundBase)
            if config.privacyMode && engine.totalEntities > 0 {
                Text("\(engine.totalEntities)")
                    .font(.caption2.bold())
                    .monospacedDigit()
                    .foregroundStyle(Color.green)
            } else if !compact {
                Text("Privacy")
                    .font(.caption2.bold())
                    .foregroundStyle(foregroundBase)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(config.privacyMode ? Color.green.opacity(0.18) : backgroundBase)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .strokeBorder(
                    config.privacyMode ? Color.green.opacity(0.6) : borderBase,
                    lineWidth: 1
                )
        )
    }

    private var helpText: String {
        if compact {
            return config.privacyMode
                ? "Privacy Mode aktiv — \(engine.totalEntities) Entitäten anonymisiert. Klick zum Deaktivieren."
                : "Privacy Mode inaktiv. Klick zum Aktivieren."
        }
        return config.privacyMode
            ? "Privacy Mode aktiv — Klick für Details / Mapping (\(engine.totalEntities) Entitäten)"
            : "Privacy Mode inaktiv — Klick für Details + Aktivieren"
    }

    private var foregroundBase: Color { compact ? Color.white.opacity(0.7) : Color.primary }
    private var backgroundBase: Color { compact ? Color.white.opacity(0.08) : Color.secondary.opacity(0.1) }
    private var borderBase: Color     { compact ? Color.white.opacity(0.15) : Color.secondary.opacity(0.2) }
}

/// Popover content launched from the Privacy pill in Office Mode. Gives the
/// user read-only visibility into the current session mapping so they can see
/// exactly which of their tokens got replaced with which placeholder.
private struct PrivacyDetailsPopover: View {
    @EnvironmentObject var config: AppConfig
    @EnvironmentObject var engine: PrivacyEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Divider()
            if config.privacyMode {
                body_active
            } else {
                body_inactive
            }
        }
        .padding(14)
        .frame(width: 380)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: config.privacyMode ? "lock.shield.fill" : "lock.shield")
                .font(.title3)
                .foregroundStyle(config.privacyMode ? Color.green : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text("Privacy Mode").font(.headline)
                Text(config.privacyMode ? "Aktiv — Session-scoped, in-memory"
                                        : "Inaktiv")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Toggle("", isOn: $config.privacyMode).labelsHidden()
        }
    }

    @ViewBuilder
    private var body_inactive: some View {
        Text("Wenn aktiv: erkannte Namen, Firmen, Orte, E-Mails, IPs, URLs und Telefonnummern werden lokal durch Platzhalter wie `[NAME_1]` ersetzt, bevor dein Text die App verlässt. Die Antwort wird zurückübersetzt.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private var body_active: some View {
        let mappings = engine.orderedMappings()
        if mappings.isEmpty {
            Text("Noch keine Entitäten erkannt. Sobald du einen Text verarbeitest, erscheinen die Ersetzungen hier.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Text("Aktuelle Session-Zuordnung")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(mappings) { entry in
                        mappingRow(entry)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 260)
            HStack {
                Text("\(mappings.count) Entität\(mappings.count == 1 ? "" : "en")")
                    .font(.caption.bold())
                    .foregroundStyle(.green)
                Spacer()
                Button("Zurücksetzen") { engine.reset() }
                    .controlSize(.small)
            }
        }
    }

    private func mappingRow(_ entry: PrivacyEngine.MappingEntry) -> some View {
        HStack(spacing: 8) {
            Text(entry.placeholder)
                .font(.system(.caption, design: .monospaced).bold())
                .foregroundStyle(color(for: entry.kind))
                .frame(minWidth: 110, alignment: .leading)
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
        .padding(.vertical, 2)
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

private struct OfficeModePill: View {
    let mode: Mode
    let isActive: Bool
    let disabled: Bool
    let action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: mode.symbolName).font(.caption2)
                Text(mode.displayName)
                    .font(.system(.caption, design: .rounded).bold())
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(isActive ? Color.accentColor : Color.secondary.opacity(0.25),
                                  lineWidth: 1)
            )
            .foregroundStyle(isActive ? Color.accentColor : .primary)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .disabled(disabled)
        .opacity(disabled ? 0.5 : 1)
    }

    private var background: Color {
        if isActive { return Color.accentColor.opacity(0.15) }
        if hovering { return Color.secondary.opacity(0.12) }
        return Color.secondary.opacity(0.05)
    }
}
