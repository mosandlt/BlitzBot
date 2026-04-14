import Foundation

struct AnthropicClient {
    let apiKey: String
    let model: String

    init(apiKey: String, model: String = "claude-sonnet-4-5") {
        self.apiKey = apiKey
        self.model = model
    }

    func rewrite(text: String, systemPrompt: String) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": 2048,
            "system": systemPrompt,
            "messages": [["role": "user", "content": text]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let msg = String(data: data, encoding: .utf8) ?? "unknown"
            throw NSError(domain: "Anthropic", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "API-Fehler: \(msg)"])
        }

        struct APIResponse: Decodable {
            struct Block: Decodable { let type: String; let text: String? }
            let content: [Block]
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        let text = decoded.content.compactMap { $0.text }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? text : text
    }
}
