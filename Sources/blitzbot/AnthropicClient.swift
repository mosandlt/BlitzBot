import Foundation

struct AnthropicClient {
    let apiKey: String
    let model: String
    let baseURL: String
    let authScheme: AuthScheme
    let sendAnthropicVersion: Bool

    init(apiKey: String,
         model: String = "claude-sonnet-4-5",
         baseURL: String = "https://api.anthropic.com",
         authScheme: AuthScheme = .apiKey,
         sendAnthropicVersion: Bool = true) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = Self.normalize(baseURL)
        self.authScheme = authScheme
        self.sendAnthropicVersion = sendAnthropicVersion
    }

    private static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func rewrite(text: String, systemPrompt: String, mode: Mode? = nil) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }

        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw LLMError.other(message: "Anthropic: ungültige URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch authScheme {
        case .apiKey: request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .none:   break
        }
        if sendAnthropicVersion {
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        }
        request.timeoutInterval = 120

        var body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": text]]
        ]
        if model == "claude-opus-4-7", let effort = mode?.opusEffort {
            body["output_config"] = ["effort": effort]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.classify(error, provider: "Anthropic")
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            struct APIErrorWrapper: Decodable {
                struct APIError: Decodable { let type: String? }
                let error: APIError?
            }
            let bodyMessage: String?
            if let errorBody = try? JSONDecoder().decode(APIErrorWrapper.self, from: data),
               let errType = errorBody.error?.type {
                switch errType {
                case "rate_limit_error":      bodyMessage = "API-Limit erreicht — bitte kurz warten"
                case "authentication_error":  bodyMessage = "API-Key ungültig"
                case "invalid_request_error": bodyMessage = "Ungültige Anfrage (Text zu lang?)"
                case "overloaded_error":      bodyMessage = "Anthropic überlastet"
                default:                      bodyMessage = "API-Fehler (\(errType))"
                }
            } else {
                bodyMessage = nil
            }
            throw LLMError.fromHTTP(statusCode: statusCode,
                                    provider: "Anthropic",
                                    bodyMessage: bodyMessage)
        }

        struct APIResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded: APIResponse
        do {
            decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw LLMError.other(message: "Anthropic: unerwartete Antwort")
        }
        let result = decoded.content.compactMap { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
