import Foundation

enum RemoteLLMError: LocalizedError {
    case noAPIKey
    case noBaseURL
    case requestFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .noAPIKey: return "API key not configured"
        case .noBaseURL: return "Base URL not configured"
        case .requestFailed(let msg): return "Request failed: \(msg)"
        case .invalidResponse: return "Invalid response from server"
        }
    }
}

actor RemoteLLMClient {
    func generate(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        provider: RemoteProvider = .custom,
        maxTokens: Int = 2048,
        temperature: Double = 0.3
    ) async throws -> String {
        guard !apiKey.isEmpty else { throw RemoteLLMError.noAPIKey }

        switch provider.apiFormat {
        case .anthropic:
            return try await generateAnthropic(
                prompt: prompt, systemPrompt: systemPrompt,
                baseURL: baseURL, apiKey: apiKey, model: model,
                apiVersion: provider.defaultApiVersion ?? "2023-06-01",
                maxTokens: maxTokens, temperature: temperature
            )
        case .openai:
            return try await generateOpenAI(
                prompt: prompt, systemPrompt: systemPrompt,
                baseURL: baseURL, apiKey: apiKey, model: model,
                maxTokens: maxTokens, temperature: temperature
            )
        }
    }

    // MARK: - OpenAI-compatible format

    private func generateOpenAI(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/chat/completions") else {
            throw RemoteLLMError.noBaseURL
        }

        var messages: [[String: String]] = []
        if let sys = systemPrompt, !sys.isEmpty {
            messages.append(["role": "system", "content": sys])
        }
        messages.append(["role": "user", "content": prompt])

        let body: [String: Any] = [
            "model": model,
            "messages": messages,
            "max_tokens": maxTokens,
            "temperature": temperature,
        ]

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = json["choices"] as? [[String: Any]],
              let first = choices.first,
              let message = first["message"] as? [String: Any],
              let content = message["content"] as? String else {
            throw RemoteLLMError.invalidResponse
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Anthropic Messages format

    private func generateAnthropic(
        prompt: String,
        systemPrompt: String?,
        baseURL: String,
        apiKey: String,
        model: String,
        apiVersion: String,
        maxTokens: Int,
        temperature: Double
    ) async throws -> String {
        let trimmedBase = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: trimmedBase + "/messages") else {
            throw RemoteLLMError.noBaseURL
        }

        var body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "temperature": temperature,
            "messages": [["role": "user", "content": prompt]],
        ]
        if let sys = systemPrompt, !sys.isEmpty {
            body["system"] = sys
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateHTTP(response, data: data)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArray = json["content"] as? [[String: Any]],
              let first = contentArray.first(where: { ($0["type"] as? String) == "text" }),
              let text = first["text"] as? String else {
            throw RemoteLLMError.invalidResponse
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Shared

    private func validateHTTP(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw RemoteLLMError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw RemoteLLMError.requestFailed("HTTP \(http.statusCode): \(body)")
        }
    }
}
