import Foundation

struct OllamaClient {
    let baseURL: String
    let model: String
    /// Optional bearer token (for authenticated Ollama deployments behind a proxy).
    let apiKey: String?

    init(baseURL: String = "http://localhost:11434",
         model: String = "llama3.2:latest",
         apiKey: String? = nil) {
        self.baseURL = baseURL.trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        self.model = model
        self.apiKey = apiKey?.isEmpty == true ? nil : apiKey
    }

    // MARK: - Chat

    func rewrite(text: String, systemPrompt: String) async throws -> String {
        guard !systemPrompt.isEmpty else { return text }
        guard let url = URL(string: "\(baseURL)/api/chat") else {
            throw NSError(domain: "Ollama", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Ungültige Ollama-URL"])
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        request.timeoutInterval = 300

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "messages": [
                ["role": "system", "content": systemPrompt],
                ["role": "user", "content": text]
            ]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NSError(domain: "Ollama", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Ollama nicht erreichbar (\(baseURL))"])
        }

        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            struct APIErrorWrapper: Decodable { let error: String? }
            let userMessage: String
            if let err = try? JSONDecoder().decode(APIErrorWrapper.self, from: data),
               let msg = err.error, !msg.isEmpty {
                // Trim to avoid huge error payloads leaking
                let safe = msg.prefix(120)
                userMessage = "Ollama-Fehler: \(safe)"
            } else if statusCode == 404 {
                userMessage = "Modell \"\(model)\" nicht installiert — via \"ollama pull \(model)\" laden"
            } else {
                userMessage = "Ollama-Fehler (HTTP \(statusCode))"
            }
            throw NSError(domain: "Ollama", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: userMessage])
        }

        struct APIResponse: Decodable {
            struct Message: Decodable { let content: String? }
            let message: Message?
        }
        let decoded = try JSONDecoder().decode(APIResponse.self, from: data)
        let result = (decoded.message?.content ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return result
    }

    // MARK: - Health check

    /// Pings `/api/tags` with a 2s timeout. Returns true only on HTTP 2xx.
    func healthCheck() async -> Bool {
        guard let url = URL(string: "\(baseURL)/api/tags") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            return (200..<300).contains(http.statusCode)
        } catch {
            return false
        }
    }

    // MARK: - Model listing

    func listModels() async throws -> [String] {
        guard let url = URL(string: "\(baseURL)/api/tags") else {
            throw NSError(domain: "Ollama", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "Ungültige Ollama-URL"])
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 2
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw NSError(domain: "Ollama", code: -2,
                          userInfo: [NSLocalizedDescriptionKey: "Ollama nicht erreichbar (\(baseURL))"])
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw NSError(domain: "Ollama", code: statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "Modell-Liste HTTP \(statusCode)"])
        }
        struct TagsResponse: Decodable {
            struct ModelEntry: Decodable { let name: String }
            let models: [ModelEntry]
        }
        let decoded = try JSONDecoder().decode(TagsResponse.self, from: data)
        return decoded.models.map { $0.name }
    }
}
