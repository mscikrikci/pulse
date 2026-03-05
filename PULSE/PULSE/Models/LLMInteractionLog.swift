import Foundation

// MARK: - Core Log Types

struct LLMInteraction: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let feature: LLMFeature
    let model: String

    // What was sent
    let systemPrompt: String
    let messages: [LoggedMessage]
    var tools: [String]?

    // What was received
    var rawResponse: String
    var parsedSuccessfully: Bool
    var toolCallsMade: [LoggedToolCall]?

    // Metadata
    var durationMs: Int
    var inputTokens: Int?
    var outputTokens: Int?
    var iterationCount: Int
}

struct LoggedMessage: Codable {
    let role: String                // "user" | "assistant"
    let content: String             // full content including injected health context
    let isInjectedContext: Bool     // true for system-injected health data blocks
}

extension LoggedMessage {
    /// Converts an Anthropic messages array entry to a LoggedMessage.
    /// Content may be a plain String or an array of content blocks (tool results).
    init(from dict: [String: Any]) {
        self.role = dict["role"] as? String ?? "unknown"

        if let text = dict["content"] as? String {
            self.content = text
        } else if let blocks = dict["content"] as? [[String: Any]] {
            // Flatten tool result blocks to a readable string
            self.content = blocks.compactMap { block -> String? in
                if let text = block["content"] as? String { return text }
                if let type = block["type"] as? String { return "[\(type) block]" }
                return nil
            }.joined(separator: "\n")
        } else {
            self.content = "(non-text content)"
        }

        // Heuristic: injected context blocks start with the === headers ContextBuilder produces
        self.isInjectedContext = content.hasPrefix("=== PULSE") || content.hasPrefix("=== HEALTH")
    }
}

struct LoggedToolCall: Codable {
    let toolName: String
    let input: String           // JSON string of inputs
    let output: String          // JSON string of result
    let durationMs: Int
}

// MARK: - Feature Enum

enum LLMFeature: String, Codable, CaseIterable {
    case morningCard   = "Morning Card"
    case checkIn       = "Mid-Day Check-In"
    case weeklyReview  = "Weekly Review"
    case chat          = "Chat"
    case agentLoop     = "Agent Loop"
}
