import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wraps Apple Intelligence's on-device language model (`FoundationModels` framework,
/// macOS 26+). No network call, no API key, no per-request cost — the model runs
/// entirely on the user's Apple-Silicon Mac once the OS has downloaded it.
///
/// Limitations vs. Claude / GPT-4 class models:
/// - ~3B-parameter on-device foundation model — strong for rewriting / tone shifts,
///   noticeably weaker for creative prompt generation or long-document reasoning
/// - Availability gated on macOS version + user opting into Apple Intelligence
/// - First use may trigger a multi-GB model download handled by the OS
///
/// The client is fully availability-guarded so the app still builds and runs on
/// macOS 13+. Older OSes receive `LLMError.other` with a clear hint.
struct AppleIntelligenceClient {
    /// Symbolic model identifier used in the Profile UI. The actual model is
    /// whatever `SystemLanguageModel.default` resolves to at runtime.
    static let modelID = "apple-on-device"

    func rewrite(text: String, systemPrompt: String) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            return try await respondUsingFoundationModels(text: text, systemPrompt: systemPrompt)
        } else {
            throw LLMError.other(message: "Apple Intelligence erfordert macOS 26 oder neuer.")
        }
        #else
        throw LLMError.other(message: "Dieser Build enthält kein Apple-Intelligence-Support.")
        #endif
    }

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private func respondUsingFoundationModels(text: String, systemPrompt: String) async throws -> String {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            break
        case .unavailable(let reason):
            throw LLMError.other(message: "Apple Intelligence nicht verfügbar: \(describe(reason))")
        @unknown default:
            throw LLMError.other(message: "Apple Intelligence: unbekannter Status")
        }

        let session = LanguageModelSession(instructions: systemPrompt)
        do {
            let response = try await session.respond(to: text)
            return response.content
        } catch {
            throw LLMError.other(message: "Apple Intelligence Fehler: \(error.localizedDescription)")
        }
    }

    @available(macOS 26.0, *)
    private func describe(_ reason: SystemLanguageModel.Availability.UnavailableReason) -> String {
        switch reason {
        case .deviceNotEligible:
            return "Gerät nicht kompatibel (Apple Silicon + genug RAM nötig)"
        case .appleIntelligenceNotEnabled:
            return "Apple Intelligence nicht in Systemeinstellungen aktiviert"
        case .modelNotReady:
            return "Modell lädt noch im Hintergrund (bitte später erneut versuchen)"
        @unknown default:
            return "unbekannter Grund"
        }
    }
    #endif
}
