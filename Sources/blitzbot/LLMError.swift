import Foundation

/// Structured error raised by LLM clients and the router.
///
/// Split into recoverable vs. non-recoverable classes. Recoverable errors
/// drive the inline recovery UI in `RecordingHUD`: the transcript is kept
/// in memory, mirrored to the pasteboard as a safety net, and the user
/// gets a 30 s window to pick a different connection profile and retry —
/// instead of losing the recording to a transient blip.
enum LLMError: Error, LocalizedError {
    /// URLSession-level failure: timeout, no internet, DNS, TLS, host unreachable.
    case connectionFailed(message: String)
    /// HTTP 401/403 — bad / expired key.
    case authFailed(statusCode: Int, message: String)
    /// HTTP 5xx — provider-side outage.
    case serverError(statusCode: Int, message: String)
    /// HTTP 4xx (other), malformed response, context-too-long, etc.
    /// Not worth offering a profile-switch retry.
    case other(message: String)

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let m),
             .authFailed(_, let m),
             .serverError(_, let m),
             .other(let m):
            return m
        }
    }

    /// `true` when the user should be offered a profile-switch retry.
    var isRecoverable: Bool {
        switch self {
        case .connectionFailed, .authFailed, .serverError: return true
        case .other:                                       return false
        }
    }

    // MARK: - Classification

    /// Wraps an arbitrary error into an `LLMError`. Idempotent for `LLMError`s.
    /// Used by call sites that receive errors from `URLSession` directly.
    static func classify(_ error: Error, provider: String) -> LLMError {
        if let llm = error as? LLMError { return llm }
        if let urlErr = error as? URLError {
            return .connectionFailed(message: userMessage(for: urlErr, provider: provider))
        }
        let ns = error as NSError
        return .other(message: ns.localizedDescription)
    }

    /// Maps an HTTP failure into the right class.
    /// `bodyMessage` is an already-sanitized human-readable hint from the provider.
    static func fromHTTP(statusCode: Int,
                         provider: String,
                         bodyMessage: String?) -> LLMError {
        let message: String = {
            if let m = bodyMessage, !m.isEmpty { return m }
            return "\(provider)-Fehler (HTTP \(statusCode))"
        }()
        switch statusCode {
        case 401, 403:       return .authFailed(statusCode: statusCode, message: message)
        case 500...599:      return .serverError(statusCode: statusCode, message: message)
        default:             return .other(message: message)
        }
    }

    private static func userMessage(for err: URLError, provider: String) -> String {
        switch err.code {
        case .notConnectedToInternet:       return "Keine Internetverbindung"
        case .timedOut:                     return "\(provider): Zeitüberschreitung"
        case .cannotFindHost,
             .cannotConnectToHost:          return "\(provider) nicht erreichbar"
        case .networkConnectionLost:        return "Verbindung unterbrochen"
        case .dnsLookupFailed:              return "DNS-Fehler"
        case .secureConnectionFailed,
             .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid:
            return "\(provider): TLS-Fehler"
        default:                            return "\(provider): Netzwerkfehler"
        }
    }
}
