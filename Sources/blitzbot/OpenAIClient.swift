import Foundation

struct OpenAIClient {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "gpt-4o-mini") {
        self.apiKey = apiKey
        self.model = model
    }

    func rewrite(text: String, systemPrompt: String) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let http = response as? HTTPURLResponse
            let statusCode = http?.statusCode ?? 0
            // Parse error type without exposing raw API response to user/logs
            struct APIErrorWrapper: Decodable {
                struct APIError: Decodable { let type: String?; let code: String? }
                let error: APIError?
            }
            let userMessage: String
            if let errorBody = try? JSONDecoder().decode(APIErrorWrapper.self, from: data),
               let err = errorBody.error {
                let errType = err.type ?? err.code ?? "unknown"
                if statusCode == 401 {
                    userMessage = "API-Key ungültig"
                } else {
                    switch errType {
                    case "invalid_api_key":
                        userMessage = "API-Key ungültig"
                    case "rate_limit_exceeded", "insufficient_quota":
                        userMessage = "API-Limit erreicht — bitte kurz warten"
                    case "context_length_exceeded":
                        userMessage = "Ungültige Anfrage (Text zu lang?)"
                    default:
                        userMessage = "API-Fehler (\(errType))"
                    }
                }
            } else {
                userMessage = "API-Fehler (HTTP \(statusCode))"
            }
            throw NSError(domain: "OpenAI", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: userMessage])
        }

        struct APIResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String? }
                let message: Message
            }
            let choices: [Choice]
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        let result = decoded.choices.compactMap { $0.message.content }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }
}
