import AppKit
import Foundation
import UserNotifications

/// Handles the macOS Services entries registered in Info.plist.
/// Each `@objc` method is referenced by `NSMessage` in an `NSServices` dict entry.
///
/// Flow:
///   1. macOS passes the selected text on the incoming pasteboard.
///   2. We read it, kick off an async LLM rewrite, then replace the selection via
///      the existing `Paster` (Cmd+V over the still-highlighted text). The service
///      call itself returns immediately — we do NOT use `NSReturnTypes`-style
///      synchronous replacement because blocking the main thread during a 1-5 s
///      API call would freeze the menubar and give no progress feedback.
///   3. On error, the clipboard keeps the original text (if fallback on) and a
///      UserNotification explains what went wrong.
@MainActor
final class ServiceProvider: NSObject {
    private weak var config: AppConfig?
    private weak var processor: ModeProcessor?

    init(config: AppConfig, processor: ModeProcessor) {
        self.config = config
        self.processor = processor
        super.init()
    }

    // MARK: - Service entry points (one per mode + default)

    @objc func rewriteDefault(_ pboard: NSPasteboard,
                              userData: String?,
                              error: AutoreleasingUnsafeMutablePointer<NSString>) {
        let mode = config?.serviceDefaultMode ?? .business
        handle(pboard: pboard, mode: mode, error: error)
    }

    @objc func rewriteBusiness(_ pboard: NSPasteboard,
                               userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handle(pboard: pboard, mode: .business, error: error)
    }

    @objc func rewritePlus(_ pboard: NSPasteboard,
                           userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handle(pboard: pboard, mode: .plus, error: error)
    }

    @objc func rewriteRage(_ pboard: NSPasteboard,
                           userData: String?,
                           error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handle(pboard: pboard, mode: .rage, error: error)
    }

    @objc func rewriteEmoji(_ pboard: NSPasteboard,
                            userData: String?,
                            error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handle(pboard: pboard, mode: .emoji, error: error)
    }

    @objc func rewritePrompt(_ pboard: NSPasteboard,
                             userData: String?,
                             error: AutoreleasingUnsafeMutablePointer<NSString>) {
        handle(pboard: pboard, mode: .aiCommand, error: error)
    }

    // MARK: - Core

    private func handle(pboard: NSPasteboard,
                        mode: Mode,
                        error: AutoreleasingUnsafeMutablePointer<NSString>) {
        guard let text = pboard.string(forType: .string), !text.isEmpty else {
            error.pointee = "Kein Text markiert"
            Log.write("SERVICE skipped: empty pasteboard (mode=\(mode.rawValue))")
            return
        }
        guard let config, let processor else {
            error.pointee = "blitzbot nicht bereit"
            return
        }

        Log.write("SERVICE start mode=\(mode.rawValue) len=\(text.count) provider=\(config.llmProvider.rawValue)")
        processor.activeMode = mode
        processor.status = .formuliert

        Task { [weak self] in
            await self?.runRewrite(text: text, mode: mode, config: config)
        }
    }

    private func runRewrite(text: String, mode: Mode, config: AppConfig) async {
        do {
            let language = detectLanguage(of: text)
            let systemPrompt = config.prompt(for: mode, language: language)
            let output: String
            if systemPrompt.isEmpty {
                output = text
            } else {
                output = try await callLLM(text: text,
                                           systemPrompt: systemPrompt,
                                           config: config)
            }
            let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                await finishError(message: "Leeres Ergebnis", originalText: text, config: config)
                return
            }
            Log.write("SERVICE ok mode=\(mode.rawValue) out=\(trimmed.count) chars")
            // Paste over the still-highlighted selection. No autoReturn for text-rewrite.
            Paster.pasteText(trimmed, autoReturn: false)
            processor?.status = .fertig
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if case .fertig = processor?.status {
                processor?.status = .bereit
                processor?.activeMode = nil
            }
        } catch {
            Log.write("SERVICE error mode=\(mode.rawValue): \(error.localizedDescription)")
            await finishError(message: error.localizedDescription,
                              originalText: text,
                              config: config)
        }
    }

    private func finishError(message: String, originalText: String, config: AppConfig) async {
        processor?.status = .fehler(message)
        if config.serviceClipboardFallback {
            // Keep original text in clipboard so user can re-try / paste manually.
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(originalText, forType: .string)
        }
        notify(title: "blitzbot: Fehler", body: message)
        try? await Task.sleep(nanoseconds: 2_000_000_000)
        processor?.clearErrorIfAny()
        processor?.activeMode = nil
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

    // MARK: - Helpers

    private func makeError(_ message: String) -> NSError {
        NSError(domain: "blitzbot.service", code: 0,
                userInfo: [NSLocalizedDescriptionKey: message])
    }

    private func notify(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let req = UNNotificationRequest(identifier: UUID().uuidString,
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req, withCompletionHandler: nil)
    }

    /// Very lightweight DE/EN detector — mirrors ModeProcessor's stopword logic but works
    /// on text already in hand (no whisper metadata). Falls back to German.
    private func detectLanguage(of text: String) -> String {
        let lowered = text.lowercased()
        let tokens = lowered.split { $0.isWhitespace || $0.isPunctuation }.map(String.init)
        guard tokens.count >= 3 else { return "de" }
        let en: Set<String> = ["the","is","a","to","of","and","in","that","it","for","with",
                               "on","this","be","are","from","as","at","by","an","or","not",
                               "have","has","was","were","will","can","would","could","should"]
        let de: Set<String> = ["der","die","das","und","ist","ich","ein","eine","nicht","mit",
                               "von","den","zu","auf","dass","für","sich","als","im","wir",
                               "habe","werden","haben","war","wird","kann","auch","bei"]
        var enHits = 0, deHits = 0
        for token in tokens {
            if en.contains(token) { enHits += 1 }
            if de.contains(token) { deHits += 1 }
        }
        if enHits > deHits { return "en" }
        return "de"
    }
}
