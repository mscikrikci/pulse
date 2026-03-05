import Foundation

struct AgentResult {
    let text: String
    let toolCallCount: Int
    let toolsSummary: [String]      // tool names called, in order
}

actor AgentRunner {
    private let client: AnthropicClient
    private let executor: ToolExecutor
    private let maxIterations = 8

    init(client: AnthropicClient, executor: ToolExecutor) {
        self.client = client
        self.executor = executor
    }

    func run(
        feature: LLMFeature,
        system: String,
        initialMessage: String,
        model: String,
        maxTokens: Int = 1024,
        tools: [[String: Any]] = AgentTools.definitions
    ) async throws -> AgentResult {
        var messages: [[String: Any]] = [["role": "user", "content": initialMessage]]
        var allToolCalls: [LoggedToolCall] = []
        let startTime = Date()
        var totalInputTokens = 0
        var totalOutputTokens = 0

        for iteration in 0..<maxIterations {
            let response = try await client.completeWithTools(
                system: system,
                messages: messages,
                tools: tools,
                model: model,
                maxTokens: maxTokens
            )
            totalInputTokens += response.inputTokens ?? 0
            totalOutputTokens += response.outputTokens ?? 0

            // No tool calls → final answer
            if response.toolCalls.isEmpty {
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                let interaction = LLMInteraction(
                    id: UUID(),
                    timestamp: startTime,
                    feature: feature,
                    model: model,
                    systemPrompt: system,
                    messages: messages.map { LoggedMessage(from: $0) },
                    tools: tools.compactMap { $0["name"] as? String },
                    rawResponse: response.text,
                    parsedSuccessfully: true,
                    toolCallsMade: allToolCalls,
                    durationMs: duration,
                    inputTokens: totalInputTokens,
                    outputTokens: totalOutputTokens,
                    iterationCount: iteration + 1
                )
                await sharedLLMLogStore.record(interaction)

                return AgentResult(
                    text: response.text,
                    toolCallCount: allToolCalls.count,
                    toolsSummary: allToolCalls.map(\.toolName)
                )
            }

            // Append assistant turn including the tool_use content blocks
            messages.append(["role": "assistant", "content": response.rawContent])

            // Execute each requested tool call and collect results
            var toolResultBlocks: [[String: Any]] = []
            for call in response.toolCalls {
                let callStart = Date()
                let result = await executor.execute(name: call.name, input: call.input)
                let callDuration = Int(Date().timeIntervalSince(callStart) * 1000)

                allToolCalls.append(LoggedToolCall(
                    toolName: call.name,
                    input: call.input.jsonString,
                    output: result,
                    durationMs: callDuration
                ))

                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": call.id,
                    "content": result
                ])
            }

            // Append tool results as the next user turn
            messages.append(["role": "user", "content": toolResultBlocks])
        }

        // Exceeded max iterations — log the failed run and throw
        let interaction = LLMInteraction(
            id: UUID(),
            timestamp: startTime,
            feature: feature,
            model: model,
            systemPrompt: system,
            messages: messages.map { LoggedMessage(from: $0) },
            tools: tools.compactMap { $0["name"] as? String },
            rawResponse: "ERROR: max iterations (\(maxIterations)) reached",
            parsedSuccessfully: false,
            toolCallsMade: allToolCalls,
            durationMs: Int(Date().timeIntervalSince(startTime) * 1000),
            inputTokens: totalInputTokens,
            outputTokens: totalOutputTokens,
            iterationCount: maxIterations
        )
        await sharedLLMLogStore.record(interaction)
        throw AppError.agentMaxIterationsReached
    }
}
