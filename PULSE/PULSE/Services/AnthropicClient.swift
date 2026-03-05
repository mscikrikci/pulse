import Foundation

// MARK: - Tool-Use Response Types

struct AnthropicToolCall {
    let id: String              // tool_use block id, needed when returning tool results
    let name: String
    let input: [String: Any]
}

struct AnthropicResponse {
    let text: String                        // empty when stop_reason is "tool_use"
    let toolCalls: [AnthropicToolCall]      // empty when stop_reason is "end_turn"
    let rawContent: [[String: Any]]         // full content array — append as-is to messages
    let inputTokens: Int?
    let outputTokens: Int?
    let stopReason: String                  // "end_turn" | "tool_use"
}

// MARK: - Client

actor AnthropicClient {
    private let apiKey: String
    private let defaultModel: String
    private let analysisModel: String
    private let session = URLSession.shared
    private var logStore: LLMInteractionStore

    private static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    // MARK: - Init

    init() throws {
        guard let key = APIKeyStore.load() else {
            throw AppError.configMissing("No API key set. Go to Settings → Anthropic API Key to add yours.")
        }
        self.apiKey = key
        // Model names can still be customised via Config.plist; defaults used if absent.
        let plistConfig = Bundle.main.path(forResource: "Config", ofType: "plist")
            .flatMap { NSDictionary(contentsOfFile: $0) }
        self.defaultModel  = plistConfig?["DefaultModel"]  as? String ?? "claude-haiku-4-5-20251001"
        self.analysisModel = plistConfig?["AnalysisModel"] as? String ?? "claude-sonnet-4-6"
        self.logStore = sharedLLMLogStore
    }

    // MARK: - Core (private)

    /// Makes a raw API call and returns the text plus token usage.
    private func rawComplete(
        system: String,
        messages: [[String: Any]],
        model: String,
        maxTokens: Int
    ) async throws -> (text: String, inputTokens: Int?, outputTokens: Int?) {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw AppError.apiFailure("No HTTP response.")
        }
        guard http.statusCode == 200 else {
            throw AppError.apiFailure("HTTP \(http.statusCode). Try again shortly.")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = json["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw AppError.apiFailure("Unexpected response format.")
        }

        let usage = json["usage"] as? [String: Any]
        let inputTokens = usage?["input_tokens"] as? Int
        let outputTokens = usage?["output_tokens"] as? Int

        return (Self.stripMarkdownFences(from: text), inputTokens, outputTokens)
    }

    /// Wraps rawComplete with timing measurement and automatic log recording.
    private func instrumentedComplete(
        feature: LLMFeature,
        system: String,
        messages: [[String: Any]],
        model: String,
        maxTokens: Int
    ) async throws -> String {
        let start = Date()

        do {
            let result = try await rawComplete(system: system, messages: messages,
                                               model: model, maxTokens: maxTokens)
            let interaction = LLMInteraction(
                id: UUID(), timestamp: start,
                feature: feature, model: model,
                systemPrompt: system,
                messages: messages.map { LoggedMessage(from: $0) },
                tools: nil,
                rawResponse: result.text, parsedSuccessfully: true,
                toolCallsMade: nil,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                inputTokens: result.inputTokens, outputTokens: result.outputTokens,
                iterationCount: 1
            )
            await logStore.record(interaction)
            return result.text

        } catch {
            let interaction = LLMInteraction(
                id: UUID(), timestamp: start,
                feature: feature, model: model,
                systemPrompt: system,
                messages: messages.map { LoggedMessage(from: $0) },
                tools: nil,
                rawResponse: "ERROR: \(error.localizedDescription)", parsedSuccessfully: false,
                toolCallsMade: nil,
                durationMs: Int(Date().timeIntervalSince(start) * 1000),
                inputTokens: nil, outputTokens: nil,
                iterationCount: 1
            )
            await logStore.record(interaction)
            throw error
        }
    }

    /// Makes an API call with tool definitions. Returns both text and any tool call requests.
    func completeWithTools(
        system: String,
        messages: [[String: Any]],
        tools: [[String: Any]],
        model: String,
        maxTokens: Int = 1024
    ) async throws -> AnthropicResponse {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        let body: [String: Any] = [
            "model": model,
            "max_tokens": maxTokens,
            "system": system,
            "messages": messages,
            "tools": tools
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            let bodyStr = String(data: data, encoding: .utf8) ?? ""
            throw AppError.apiFailure("HTTP error. \(String(bodyStr.prefix(200)))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let contentArr = json["content"] as? [[String: Any]] else {
            throw AppError.apiFailure("Unexpected response format from API.")
        }

        let stopReason = json["stop_reason"] as? String ?? "end_turn"
        let usage = json["usage"] as? [String: Any]

        var textParts: [String] = []
        var toolCalls: [AnthropicToolCall] = []

        for block in contentArr {
            guard let type = block["type"] as? String else { continue }
            if type == "text", let text = block["text"] as? String {
                textParts.append(text)
            } else if type == "tool_use",
                      let id = block["id"] as? String,
                      let name = block["name"] as? String,
                      let input = block["input"] as? [String: Any] {
                toolCalls.append(AnthropicToolCall(id: id, name: name, input: input))
            }
        }

        return AnthropicResponse(
            text: Self.stripMarkdownFences(from: textParts.joined(separator: "\n")),
            toolCalls: toolCalls,
            rawContent: contentArr,
            inputTokens: usage?["input_tokens"] as? Int,
            outputTokens: usage?["output_tokens"] as? Int,
            stopReason: stopReason
        )
    }

    /// Strips ```json ... ``` or ``` ... ``` wrappers the LLM sometimes adds.
    static func stripMarkdownFences(from text: String) -> String {
        var s = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```") {
            s = s.drop(while: { $0 != "\n" }).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if s.hasSuffix("```") {
            s = String(s.dropLast(3)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s
    }

    // MARK: - Convenience (feature-specific)

    func completeMorningCard(context: String) async throws -> String {
        try await instrumentedComplete(
            feature: .morningCard,
            system: Prompts.system,
            messages: [["role": "user", "content": context + "\n\n" + Prompts.morningCardInstruction]],
            model: defaultModel,
            maxTokens: 1024
        )
    }

    func completeWeeklyReview(context: String) async throws -> String {
        try await instrumentedComplete(
            feature: .weeklyReview,
            system: Prompts.system,
            messages: [["role": "user", "content": context + "\n\n" + Prompts.weeklyReviewInstruction]],
            model: analysisModel,
            maxTokens: 2048
        )
    }

    func completeCheckIn(context: String) async throws -> String {
        try await instrumentedComplete(
            feature: .checkIn,
            system: Prompts.system,
            messages: [["role": "user", "content": context + "\n\n" + Prompts.checkInInstruction]],
            model: defaultModel,
            maxTokens: 512
        )
    }

    func completeChat(context: String, history: [[String: Any]]) async throws -> String {
        let isComplex = context.contains("week") || context.contains("month") ||
                        context.contains("trend") || context.contains("goal progress")
        let model = isComplex ? analysisModel : defaultModel
        var messages = history
        messages.append(["role": "user", "content": context + "\n\n" + Prompts.chatInstruction])
        return try await instrumentedComplete(
            feature: .chat,
            system: Prompts.system,
            messages: messages,
            model: model,
            maxTokens: 1024
        )
    }
}
