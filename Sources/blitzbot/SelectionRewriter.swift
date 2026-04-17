import AppKit
import ApplicationServices
import Foundation

/// Captures the currently selected text from the focused app, for any caller
/// (`SelectionRewriter`'s fire-and-forget ⌘⌥0 flow + Office Mode's preview window).
///
/// Strategy: AX API first (reads `AXSelectedText` directly, works in most native
/// apps without a keyboard round-trip). Falls back to simulating ⌘C, reading the
/// pasteboard diff, and restoring the previous pasteboard contents — so the user's
/// clipboard history stays intact.
@MainActor
enum TextSelectionGrabber {
    /// Returns the selected text, or empty string if nothing is selected / AX fails.
    static func grab() -> String {
        if let ax = axSelection(), !ax.isEmpty { return ax }
        return clipboardCopyFallback()
    }

    private static func axSelection() -> String? {
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

    private static func clipboardCopyFallback() -> String {
        let pb = NSPasteboard.general
        let previous = pb.string(forType: .string)
        let prevChangeCount = pb.changeCount

        simulateCommandC()
        let deadline = Date().addingTimeInterval(0.25)
        while pb.changeCount == prevChangeCount && Date() < deadline {
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }
        let captured = pb.string(forType: .string) ?? ""

        if let previous {
            pb.clearContents()
            pb.setString(previous, forType: .string)
        }
        return captured
    }

    private static func simulateCommandC() {
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
}

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

    /// Delegates to the shared `TextSelectionGrabber` utility at the top of this file
    /// so Office Mode can use the same AX → ⌘C fallback code path.
    private func grabSelection() -> String {
        TextSelectionGrabber.grab()
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
        try await LLMRouter.rewrite(text: text, systemPrompt: systemPrompt, config: config)
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
