import AppKit
import ApplicationServices
import Foundation

/// Rewrites the currently selected text via the configured default mode.
///
/// Triggered by the `rewriteSelection` global hotkey. Flow:
///   1. Try to read the focused element's `AXSelectedText` attribute.
///   2. Fallback: simulate ⌘C, read clipboard (restore previous clipboard after).
///   3. Call the configured LLM provider with the mode's system prompt.
///   4. Paste result (replaces selection in apps that highlight it).
///
/// This exists because macOS Services integration doesn't work for
/// non-notarized (self-signed) apps — Gatekeeper rejects them at the
/// `pbs` level. The hotkey path uses only Accessibility, which the user
/// has already granted.
@MainActor
final class SelectionRewriter {
    private weak var config: AppConfig?
    private weak var processor: ModeProcessor?
    private var busy = false

    init(config: AppConfig, processor: ModeProcessor) {
        self.config = config
        self.processor = processor
    }

    func rewriteSelection() {
        guard !busy else {
            Log.write("rewriteSelection skipped: already busy")
            return
        }
        guard let config, let processor else { return }
        let mode = config.serviceDefaultMode

        // Don't hijack while a voice recording is active.
        if case .aufnahme = processor.status {
            Log.write("rewriteSelection skipped: voice recording in progress")
            return
        }

        busy = true
        let text = grabSelection()
        guard !text.isEmpty else {
            Log.write("rewriteSelection: no selection, abort")
            processor.status = .fehler("Kein Text markiert")
            scheduleErrorClear()
            busy = false
            return
        }

        Log.write("rewriteSelection start mode=\(mode.rawValue) len=\(text.count) provider=\(config.llmProvider.rawValue)")
        processor.activeMode = mode
        processor.status = .formuliert

        Task { [weak self] in
            await self?.run(text: text, mode: mode, config: config)
            self?.busy = false
        }
    }

    // MARK: - Selection acquisition

    /// Primary: AX API. Fallback: ⌘C + clipboard diff.
    private func grabSelection() -> String {
        if let ax = axSelection(), !ax.isEmpty { return ax }
        return clipboardCopyFallback()
    }

    private func axSelection() -> String? {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedErr = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusedErr == .success, let focused else { return nil }
        let element = focused as! AXUIElement
        var selected: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &selected
        )
        guard err == .success, let text = selected as? String else { return nil }
        return text
    }

    /// Simulates ⌘C, reads pasteboard, then restores the previous pasteboard contents.
    /// Only used when AX doesn't expose a selection (e.g., many Electron apps).
    private func clipboardCopyFallback() -> String {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let prevChangeCount = pb.changeCount

        simulateCommandC()
        // Wait briefly for the copy to land
        let deadline = Date().addingTimeInterval(0.25)
        while pb.changeCount == prevChangeCount && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let captured = pb.string(forType: .string) ?? ""

        // Restore previous pasteboard so we don't trash the user's clipboard.
        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
        return captured
    }

    private func simulateCommandC() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let cKey: CGKeyCode = 8
        let down = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: source, virtualKey: cKey, keyDown: false)
        up?.flags = .maskCommand
        let tap: CGEventTapLocation = .cgAnnotatedSessionEventTap
        down?.post(tap: tap)
        usleep(15_000)
        up?.post(tap: tap)
    }

    // MARK: - Pipeline

    private func run(text: String, mode: Mode, config: AppConfig) async {
        do {
            let language = detectLanguage(of: text)
            let systemPrompt = config.prompt(for: mode, language: language)
            let output: String
            if systemPrompt.isEmpty {
                output = text
            } else {
                output = try await callLLM(text: text, systemPrompt: systemPrompt, config: config)
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                processor?.status = .fehler("Leeres Ergebnis")
                scheduleErrorClear()
                return
            }
            Log.write("rewriteSelection ok mode=\(mode.rawValue) out=\(trimmed.count)")
            Paster.pasteText(trimmed, autoReturn: false)
            processor?.status = .fertig
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if case .fertig = processor?.status {
                processor?.status = .bereit
                processor?.activeMode = nil
            }
        } catch {
            Log.write("rewriteSelection error mode=\(mode.rawValue): \(error.localizedDescription)")
            processor?.status = .fehler(error.localizedDescription)
            scheduleErrorClear()
        }
    }

    private func scheduleErrorClear() {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            self?.processor?.clearErrorIfAny()
            self?.processor?.activeMode = nil
        }
    }

    private func callLLM(text: String,
                         systemPrompt: String,
                         config: AppConfig) async throws -> String {
        switch config.llmProvider {
        case .anthropic:
            guard let apiKey = KeychainStore.loadAPIKey(), !apiKey.isEmpty else {
                throw makeError("Kein Anthropic API Key")
            }
            let client = AnthropicClient(apiKey: apiKey, model: config.model)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)
        case .openai:
            guard let apiKey = KeychainStore.loadOpenAIKey(), !apiKey.isEmpty else {
                throw makeError("Kein OpenAI API Key")
            }
            let client = OpenAIClient(apiKey: apiKey, model: config.openaiModel)
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)
        case .ollama:
            let client = OllamaClient(baseURL: config.ollamaBaseURL,
                                      model: config.ollamaModel,
                                      apiKey: KeychainStore.loadOllamaKey())
            return try await client.rewrite(text: text, systemPrompt: systemPrompt)
        }
    }

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "blitzbot.rewrite", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func detectLanguage(of text: String) -> String {
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
