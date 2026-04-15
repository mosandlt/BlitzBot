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

    func rewrite(text: String, systemPrompt: String) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }

        guard let url = URL(string: "\(baseURL)/v1/messages") else {
            throw NSError(domain: "Anthropic", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Ungültige URL"])
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

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": text]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            let statusCode = http?.statusCode ?? 0
            struct APIErrorWrapper: Decodable {
                struct APIError: Decodable { let type: String? }
                let error: APIError?
            }
            let userMessage: String
            if let errorBody = try? JSONDecoder().decode(APIErrorWrapper.self, from: data),
               let errType = errorBody.error?.type {
                switch errType {
                case "rate_limit_error":    userMessage = "API-Limit erreicht — bitte kurz warten"
                case "authentication_error": userMessage = "API-Key ungültig"
                case "invalid_request_error": userMessage = "Ungültige Anfrage (Text zu lang?)"
                default:                    userMessage = "API-Fehler (\(errType))"
                }
            } else {
                userMessage = "API-Fehler (HTTP \(statusCode))"
            }
            throw NSError(domain: "Anthropic", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: userMessage])
        }

        struct APIResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        let result = decoded.content.compactMap { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
