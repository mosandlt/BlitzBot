import Foundation

struct OpenAIClient {
    let apiKey: String
    let model: String
    let baseURL: String
    let authScheme: AuthScheme

    init(apiKey: String,
         model: String = "gpt-4o-mini",
         baseURL: String = "https://api.openai.com",
         authScheme: AuthScheme = .bearer) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = Self.normalize(baseURL)
        self.authScheme = authScheme
    }

    private static func normalize(_ url: String) -> String {
        var s = url.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasSuffix("/") { s.removeLast() }
        return s
    }

    func rewrite(text: String, systemPrompt: String) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }

        guard let url = URL(string: "\(baseURL)/v1/chat/completions") else {
            throw LLMError.other(message: "OpenAI: ungültige URL")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        switch authScheme {
        case .bearer: request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .apiKey: request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        case .none:   break
        }
        request.timeoutInterval = 120

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw LLMError.classify(error, provider: "OpenAI")
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            struct APIErrorWrapper: Decodable {
                struct APIError: Decodable { let type: String?; let code: String? }
                let error: APIError?
            }
            let bodyMessage: String?
            if let errorBody = try? JSONDecoder().decode(APIErrorWrapper.self, from: data),
               let err = errorBody.error {
                let errType = err.type ?? err.code ?? "unknown"
                if statusCode == 401 {
                    bodyMessage = "API-Key ungültig"
                } else {
                    switch errType {
                    case "invalid_api_key":
                        bodyMessage = "API-Key ungültig"
                    case "rate_limit_exceeded", "insufficient_quota":
                        bodyMessage = "API-Limit erreicht — bitte kurz warten"
                    case "context_length_exceeded":
                        bodyMessage = "Ungültige Anfrage (Text zu lang?)"
                    default:
                        bodyMessage = "API-Fehler (\(errType))"
                    }
                }
            } else {
                bodyMessage = nil
            }
            throw LLMError.fromHTTP(statusCode: statusCode,
                                    provider: "OpenAI",
                                    bodyMessage: bodyMessage)
        }

        struct APIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded: APIResponse
        do {
            decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        } catch {
            throw LLMError.other(message: "OpenAI: unerwartete Antwort")
        }
        let result = decoded.choices.compactMap { $0.message.content }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
