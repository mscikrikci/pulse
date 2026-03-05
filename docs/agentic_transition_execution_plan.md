# Pulse — Agentic Transition: Detailed Execution Plan
## File-by-file implementation guide for Phases A, B, and C

_Based on: `docs/agentic_transition_roadmap.md`_
_Current codebase state: v1.0 complete (all 6 development phases done)_

---

## How to Use This Document

Each section lists **exact file changes** with function signatures, integration points, and validation criteria. Work top-to-bottom within each phase. Do not skip ahead. Treat each numbered step as a commit-worthy unit.

---

## Phase A: LLM Interaction Log
**Estimated effort:** 1–2 days
**Risk:** Low — purely additive, zero changes to existing LLM call behavior

---

### A-1. Add `agentMaxIterationsReached` to AppError

**File:** `PULSE/Models/AppError.swift`

Add one new case and its `errorDescription`:

```swift
case agentMaxIterationsReached

// in errorDescription switch:
case .agentMaxIterationsReached:
    return "The AI took too many steps to answer this. Try asking a more specific question."
```

Do this now even though it's used in Phase B — it keeps AppError as the single source of error truth.

---

### A-2. Create `Models/LLMInteractionLog.swift`

New file. Paste verbatim from the roadmap:

```swift
import Foundation

struct LLMInteraction: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let feature: LLMFeature
    let model: String
    let systemPrompt: String
    let messages: [LoggedMessage]
    var tools: [String]?
    var rawResponse: String
    var parsedSuccessfully: Bool
    var toolCallsMade: [LoggedToolCall]?
    var durationMs: Int
    var inputTokens: Int?
    var outputTokens: Int?
    var iterationCount: Int
}

struct LoggedMessage: Codable {
    let role: String
    let content: String
    let isInjectedContext: Bool
}

struct LoggedToolCall: Codable {
    let toolName: String
    let input: String       // JSON string
    let output: String      // JSON string
    let durationMs: Int
}

enum LLMFeature: String, Codable, CaseIterable {
    case morningCard   = "Morning Card"
    case checkIn       = "Mid-Day Check-In"
    case weeklyReview  = "Weekly Review"
    case chat          = "Chat"
    case agentLoop     = "Agent Loop"
}
```

Add a convenience init to `LoggedMessage` for converting from `[String: Any]`:

```swift
extension LoggedMessage {
    init(from dict: [String: Any]) {
        self.role = dict["role"] as? String ?? "unknown"
        // Content may be a String or an array (tool results) — flatten to string
        if let text = dict["content"] as? String {
            self.content = text
        } else if let arr = dict["content"] as? [[String: Any]] {
            self.content = arr.compactMap { $0["content"] as? String }.joined(separator: "\n")
        } else {
            self.content = "(non-text content)"
        }
        // Heuristic: injected context blocks start with the === headers ContextBuilder produces
        self.isInjectedContext = self.content.hasPrefix("=== PULSE") || self.content.hasPrefix("=== HEALTH")
    }
}
```

---

### A-3. Create `Models/LLMInteractionStore.swift`

```swift
import Foundation

actor LLMInteractionStore {
    private var interactions: [LLMInteraction] = []
    private let fileURL: URL
    private let maxRetained = 200

    private init(interactions: [LLMInteraction], fileURL: URL) {
        self.interactions = interactions
        self.fileURL = fileURL
    }

    static func load() async -> LLMInteractionStore {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return LLMInteractionStore(interactions: [], fileURL: URL(fileURLWithPath: ""))
        }
        let url = docs.appendingPathComponent("llm_log.json")
        if FileManager.default.fileExists(atPath: url.path),
           let raw = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode([LLMInteraction].self, from: raw) {
            return LLMInteractionStore(interactions: decoded, fileURL: url)
        }
        return LLMInteractionStore(interactions: [], fileURL: url)
    }

    func record(_ interaction: LLMInteraction) async {
        interactions.append(interaction)
        if interactions.count > maxRetained {
            interactions.removeFirst(interactions.count - maxRetained)
        }
        save()
    }

    func recent(limit: Int = 50) -> [LLMInteraction] {
        Array(interactions.suffix(limit).reversed())
    }

    func forFeature(_ feature: LLMFeature) -> [LLMInteraction] {
        Array(interactions.filter { $0.feature == feature }.reversed())
    }

    private func save() {
        guard !fileURL.path.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(interactions) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
```

**Note:** `save()` is synchronous and private — it's called only from within the actor, so no `await` needed.

---

### A-4. Modify `AnthropicClient.swift`

Three changes:

**4a. Add `logStore` property and update `init()`:**

```swift
actor AnthropicClient {
    private let apiKey: String
    private let defaultModel: String
    private let analysisModel: String
    private let session = URLSession.shared
    private let logStore: LLMInteractionStore   // ADD THIS

    init() throws {
        // ... existing config loading unchanged ...
        self.logStore = await LLMInteractionStore.load()  // ADD THIS
    }
```

Wait — `init()` cannot be `async` while also being a throwing `init`. Fix: make `logStore` a `var` initialized to a temporary value, then updated after init. Actually the cleanest approach: initialize with a synchronous empty store and kick off async load separately.

Better pattern: make `logStore` a `let` with a lazy load pattern:

```swift
// Keep logStore as a var initialized synchronously, replace with loaded version lazily
private var logStore = LLMInteractionStore.makeEmpty()

// In AnthropicClient, after all current init code, add:
Task { logStore = await LLMInteractionStore.load() }
```

Add `makeEmpty()` static to `LLMInteractionStore`:
```swift
static func makeEmpty() -> LLMInteractionStore {
    LLMInteractionStore(interactions: [], fileURL: URL(fileURLWithPath: ""))
}
```

This means the first call after cold app launch may not have the full log loaded, but that's fine — we only read from `logStore` in the Log UI, not in critical paths.

**4b. Rename existing `complete()` to `rawComplete()`, keep signature identical:**

```swift
private func rawComplete(
    system: String,
    messages: [[String: Any]],
    model: String,
    maxTokens: Int
) async throws -> (text: String, inputTokens: Int?, outputTokens: Int?) {
    // ... same URLRequest construction ...
    // ... same URLSession call ...
    // Change the final return to also surface token counts:
    let inputTokens = (json["usage"] as? [String: Any])?["input_tokens"] as? Int
    let outputTokens = (json["usage"] as? [String: Any])?["output_tokens"] as? Int
    let text = Self.stripMarkdownFences(from: first["text"] as? String ?? "")
    return (text, inputTokens, outputTokens)
}
```

**4c. Add public `instrumentedComplete()` that all feature methods will call:**

```swift
private func instrumentedComplete(
    feature: LLMFeature,
    system: String,
    messages: [[String: Any]],
    model: String,
    maxTokens: Int
) async throws -> String {
    let start = Date()
    var rawResponse = ""
    var parsedOK = false
    var inputTok: Int? = nil
    var outputTok: Int? = nil

    do {
        let result = try await rawComplete(system: system, messages: messages,
                                           model: model, maxTokens: maxTokens)
        rawResponse = result.text
        inputTok = result.inputTokens
        outputTok = result.outputTokens
        parsedOK = true

        let interaction = LLMInteraction(
            id: UUID(), timestamp: start, feature: feature, model: model,
            systemPrompt: system,
            messages: messages.map { LoggedMessage(from: $0) },
            tools: nil,
            rawResponse: rawResponse, parsedSuccessfully: parsedOK,
            toolCallsMade: nil,
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            inputTokens: inputTok, outputTokens: outputTok, iterationCount: 1
        )
        await logStore.record(interaction)
        return rawResponse

    } catch {
        let interaction = LLMInteraction(
            id: UUID(), timestamp: start, feature: feature, model: model,
            systemPrompt: system,
            messages: messages.map { LoggedMessage(from: $0) },
            tools: nil,
            rawResponse: "ERROR: \(error.localizedDescription)", parsedSuccessfully: false,
            toolCallsMade: nil,
            durationMs: Int(Date().timeIntervalSince(start) * 1000),
            inputTokens: nil, outputTokens: nil, iterationCount: 1
        )
        await logStore.record(interaction)
        throw error
    }
}
```

**4d. Update the four convenience methods to use `instrumentedComplete()`:**

```swift
func completeMorningCard(context: String) async throws -> String {
    try await instrumentedComplete(
        feature: .morningCard,
        system: Prompts.system,
        messages: [["role": "user", "content": context + "\n\n" + Prompts.morningCardInstruction]],
        model: defaultModel, maxTokens: 1024
    )
}

func completeWeeklyReview(context: String) async throws -> String {
    try await instrumentedComplete(
        feature: .weeklyReview,
        system: Prompts.system,
        messages: [["role": "user", "content": context + "\n\n" + Prompts.weeklyReviewInstruction]],
        model: analysisModel, maxTokens: 2048
    )
}

func completeCheckIn(context: String) async throws -> String {
    try await instrumentedComplete(
        feature: .checkIn,
        system: Prompts.system,
        messages: [["role": "user", "content": context + "\n\n" + Prompts.checkInInstruction]],
        model: defaultModel, maxTokens: 512
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
        model: model, maxTokens: 1024
    )
}
```

The old public `complete()` method can be removed — it's replaced by `rawComplete()` (private) and `instrumentedComplete()` (private).

---

### A-5. Create `Views/Settings/LLMLogView.swift`

New file. A developer-accessible debug panel:

```swift
import SwiftUI

struct LLMLogView: View {
    let logStore: LLMInteractionStore
    @State private var interactions: [LLMInteraction] = []
    @State private var selectedFeature: LLMFeature? = nil
    @State private var selectedInteraction: LLMInteraction? = nil

    var filtered: [LLMInteraction] {
        guard let f = selectedFeature else { return interactions }
        return interactions.filter { $0.feature == f }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Feature filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(nil, label: "All")
                    ForEach(LLMFeature.allCases, id: \.self) { f in
                        filterChip(f, label: f.rawValue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()
            List(filtered) { interaction in
                Button { selectedInteraction = interaction } label: {
                    LLMLogRowView(interaction: interaction)
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
        }
        .navigationTitle("LLM Log")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedInteraction) { i in
            LLMLogDetailView(interaction: i)
        }
        .task {
            interactions = await logStore.recent(limit: 200)
        }
    }

    private func filterChip(_ feature: LLMFeature?, label: String) -> some View {
        Button(label) { selectedFeature = feature }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background((selectedFeature == feature) ? Color.blue : Color(.secondarySystemBackground))
            .foregroundStyle((selectedFeature == feature) ? Color.white : Color.primary)
            .clipShape(Capsule())
    }
}

struct LLMLogRowView: View {
    let interaction: LLMInteraction
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(interaction.feature.rawValue)
                        .font(.subheadline.weight(.medium))
                    if !interaction.parsedSuccessfully {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
                Text(interaction.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(interaction.model.contains("haiku") ? "haiku" : "sonnet")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                let inTok = interaction.inputTokens.map { "\($0)in" } ?? "?"
                let outTok = interaction.outputTokens.map { "\($0)out" } ?? "?"
                Text("\(interaction.durationMs)ms · \(inTok)/\(outTok)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct LLMLogDetailView: View {
    let interaction: LLMInteraction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header metadata
                    metaBlock

                    // System prompt
                    logSection(title: "SYSTEM PROMPT", content: interaction.systemPrompt)

                    // Messages
                    ForEach(interaction.messages.indices, id: \.self) { i in
                        let msg = interaction.messages[i]
                        logSection(title: "[\(msg.role.uppercased())]", content: msg.content)
                    }

                    // Tool calls (Phase B — nil in Phase A)
                    if let toolCalls = interaction.toolCallsMade, !toolCalls.isEmpty {
                        ForEach(toolCalls.indices, id: \.self) { i in
                            let call = toolCalls[i]
                            logSection(
                                title: "TOOL: \(call.toolName) (\(call.durationMs)ms)",
                                content: "IN: \(call.input)\n\nOUT: \(call.output)"
                            )
                        }
                    }

                    // Raw response
                    logSection(title: "RAW RESPONSE", content: interaction.rawResponse)
                }
                .padding()
            }
            .navigationTitle("\(interaction.feature.rawValue) Detail")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: exportText) {
                        Label("Share", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("\(interaction.feature.rawValue) — \(interaction.timestamp.formatted())")
                .font(.headline)
            Text("Model: \(interaction.model)")
                .font(.caption)
            let status = interaction.parsedSuccessfully ? "✓ Parsed" : "✗ Parse failed"
            Text("\(interaction.durationMs)ms · \(interaction.inputTokens ?? 0)→\(interaction.outputTokens ?? 0) tokens · \(status)")
                .font(.caption)
                .foregroundStyle(interaction.parsedSuccessfully ? .secondary : .red)
            if interaction.iterationCount > 1 {
                Text("Iterations: \(interaction.iterationCount)")
                    .font(.caption)
                    .foregroundStyle(.blue)
            }
        }
    }

    private func logSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("──── \(title) ────")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    private var exportText: String {
        var lines: [String] = []
        lines.append("\(interaction.feature.rawValue) — \(interaction.timestamp)")
        lines.append("Model: \(interaction.model) | \(interaction.durationMs)ms | \(interaction.inputTokens ?? 0)→\(interaction.outputTokens ?? 0) tokens")
        lines.append("Parsed: \(interaction.parsedSuccessfully)")
        lines.append("")
        lines.append("=== SYSTEM PROMPT ===")
        lines.append(interaction.systemPrompt)
        for msg in interaction.messages {
            lines.append("")
            lines.append("=== [\(msg.role.uppercased())] ===")
            lines.append(msg.content)
        }
        if let tools = interaction.toolCallsMade {
            for call in tools {
                lines.append("")
                lines.append("=== TOOL: \(call.toolName) ===")
                lines.append("IN: \(call.input)")
                lines.append("OUT: \(call.output)")
            }
        }
        lines.append("")
        lines.append("=== RAW RESPONSE ===")
        lines.append(interaction.rawResponse)
        return lines.joined(separator: "\n")
    }
}
```

---

### A-6. Wire LLM Log into the App

**Option:** Add a hidden access mechanism. Simplest approach: add a "Developer" section to a settings sheet or add a triple-tap gesture on the version number already shown somewhere.

If there's no settings view yet, add a minimal one. Find where the app version is displayed, or add a tap gesture to the tab bar area.

In `ContentView.swift` or wherever the tab bar root lives, add a `@State private var showLLMLog = false` and a hidden tap target:

```swift
// Somewhere in the view hierarchy — e.g., a long-press on the navigation title
.onLongPressGesture(minimumDuration: 2) {
    showLLMLog = true
}
.sheet(isPresented: $showLLMLog) {
    NavigationStack {
        LLMLogView(logStore: /* pass logStore reference */)
    }
}
```

The `logStore` reference needs to be accessible from the UI. The cleanest path: make `LLMInteractionStore` a singleton or pass it through the environment. For v1, a simple `@Environment` value or app-level `@State` on the root is fine.

**Practical approach:** Store it in `PulseApp.swift` as a property, pass down via environment:

```swift
// PulseApp.swift
@State private var llmLogStore = LLMInteractionStore.makeEmpty()

// In .task on the WindowGroup:
.task { llmLogStore = await LLMInteractionStore.load() }
.environment(llmLogStore)
```

Then `AnthropicClient` and `LLMLogView` both read from it via environment or direct injection.

**Note:** Since `AnthropicClient` is an actor, sharing the same store instance requires passing it at `AnthropicClient` init time rather than reading from environment. Update the `AnthropicClient.init()` to accept an optional `logStore: LLMInteractionStore?` parameter.

---

### A-7. Phase A Validation Checklist

Before moving to Phase B, verify:

- [ ] Every morning card generation creates an entry in the log
- [ ] Every check-in generation creates an entry
- [ ] Every weekly review generation creates an entry
- [ ] Every chat message creates an entry
- [ ] `llm_log.json` is written to Documents and survives app restart
- [ ] LLM Log UI shows the list, filtered correctly by feature
- [ ] Tapping a row shows full system prompt + context block + raw response
- [ ] Share button exports a readable `.txt` file
- [ ] Parse failures (force a bad JSON response manually) show ✗ in the log
- [ ] Token counts appear after a real API call

---

## Phase B: Agentic Tool Loop
**Estimated effort:** 1–2 weeks
**Risk:** Medium — migrate features one at a time; keep feature flags

**Prerequisite:** Phase A complete and LLM Log UI working.

---

### B-1. Add Tool-Use Support to `AnthropicClient`

The Anthropic API returns `tool_use` content blocks alongside (or instead of) text blocks when the model wants to call a tool. The existing `rawComplete()` only handles `text` blocks.

**New response model:**

```swift
// Add to LLMInteractionLog.swift or a new file AnthropicResponse.swift

struct AnthropicToolCall {
    let id: String       // tool_use block id from API
    let name: String
    let input: [String: Any]
}

struct AnthropicResponse {
    let text: String                    // empty string if stop_reason is "tool_use"
    let toolCalls: [AnthropicToolCall]  // empty if stop_reason is "end_turn"
    let rawContent: [[String: Any]]     // full content array, for appending to messages
    let usage: (inputTokens: Int?, outputTokens: Int?)
    let stopReason: String              // "end_turn" | "tool_use"
}
```

**New method on `AnthropicClient`:**

```swift
func completeWithTools(
    system: String,
    messages: [[String: Any]],
    tools: [[String: Any]],
    model: String,
    maxTokens: Int
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
        let body = String(data: data, encoding: .utf8) ?? ""
        throw AppError.apiFailure("HTTP error. \(body.prefix(200))")
    }

    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
          let contentArr = json["content"] as? [[String: Any]] else {
        throw AppError.apiFailure("Unexpected response format.")
    }

    let stopReason = json["stop_reason"] as? String ?? "end_turn"
    let usage = json["usage"] as? [String: Any]
    let inputTokens = usage?["input_tokens"] as? Int
    let outputTokens = usage?["output_tokens"] as? Int

    // Parse content blocks
    var textParts: [String] = []
    var toolCalls: [AnthropicToolCall] = []

    for block in contentArr {
        let type = block["type"] as? String ?? ""
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
        text: textParts.joined(separator: "\n"),
        toolCalls: toolCalls,
        rawContent: contentArr,
        usage: (inputTokens, outputTokens),
        stopReason: stopReason
    )
}
```

---

### B-2. Create `Services/AgentTools.swift`

New file. Six tool definitions as a static constant. Copy from the roadmap exactly — the tool definitions are final.

One addition not in the roadmap: a helper for encoding the input dict to a JSON string (needed for logging):

```swift
import Foundation

enum AgentTools {
    static let definitions: [[String: Any]] = [
        // ... exact definitions from roadmap section B.2 ...
    ]
}

extension [String: Any] {
    var jsonString: String {
        guard let data = try? JSONSerialization.data(withJSONObject: self, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
```

---

### B-3. Create `Services/ToolExecutor.swift`

New actor. Receives references to all stores at init. Implements the six tool methods.

**Structure:**

```swift
import Foundation

actor ToolExecutor {
    private let trendStore: TrendStore
    private let goalStore: GoalStore
    private let progressStore: ProgressStore
    private let protocolMatcher = ProtocolMatcher()

    init(trendStore: TrendStore, goalStore: GoalStore, progressStore: ProgressStore) {
        self.trendStore = trendStore
        self.goalStore = goalStore
        self.progressStore = progressStore
    }

    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        case "get_health_data":    return await getHealthData(input: input)
        case "get_trend_stats":    return await getTrendStats(input: input)
        case "get_baseline":       return await getBaseline(input: input)
        case "get_goal_progress":  return await getGoalProgress(input: input)
        case "get_protocols":      return await getProtocols(input: input)
        case "get_correlation":    return await getCorrelation(input: input)
        default:
            return encodeError("Unknown tool: \(name)")
        }
    }
}
```

**Implement each tool method:**

**`getHealthData`:**
```swift
private func getHealthData(input: [String: Any]) async -> String {
    let history = await trendStore.history
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyy-MM-dd"
    let today = dateFormatter.string(from: Date())
    let yesterday = dateFormatter.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

    var entries: [DayEntry]

    if let daysBack = input["days_back"] as? Int {
        let cutoff = Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
        let cutoffKey = dateFormatter.string(from: cutoff)
        entries = history.filter { $0.date >= cutoffKey }
    } else if let dateStr = input["date"] as? String {
        let resolvedDate = dateStr == "today" ? today : (dateStr == "yesterday" ? yesterday : dateStr)
        entries = history.filter { $0.date == resolvedDate }
    } else {
        entries = history.suffix(7).map { $0 }
    }

    // Sort chronologically
    entries.sort { $0.date < $1.date }

    guard !entries.isEmpty else {
        return encode(["data_available": false, "reason": "No data for requested window"])
    }

    let result: [String: Any] = [
        "data_available": true,
        "days_returned": entries.count,
        "entries": entries.map { dayEntryToDict($0) }
    ]
    return encode(result)
}

private func dayEntryToDict(_ e: DayEntry) -> [String: Any] {
    var d: [String: Any] = ["date": e.date]
    if let v = e.hrv { d["hrv_ms"] = v }
    if let v = e.restingHR { d["resting_hr_bpm"] = v }
    if let v = e.sleepHours { d["sleep_hours"] = v }
    if let v = e.sleepEfficiency { d["sleep_efficiency"] = v }
    if let v = e.respiratoryRate { d["respiratory_rate"] = v }
    if let v = e.activeCalories { d["active_calories"] = v }
    if let v = e.steps { d["steps"] = v }
    if let v = e.alcoholReported { d["alcohol_reported"] = v }
    if let v = e.events, !v.isEmpty { d["events"] = v }
    return d
}
```

**`getTrendStats`:**
```swift
private func getTrendStats(input: [String: Any]) async -> String {
    guard let metric = input["metric"] as? String,
          let days = input["days"] as? Int else {
        return encodeError("metric and days are required")
    }

    let history = await trendStore.history
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
    let cutoffKey = formatter.string(from: cutoff)

    let window = history.filter { $0.date >= cutoffKey }
    let values: [Double] = window.compactMap { metricValue(entry: $0, metric: metric) }

    guard !values.isEmpty else {
        return encode(["data_available": false, "metric": metric, "days_requested": days, "days_available": 0])
    }

    let mean = values.reduce(0, +) / Double(values.count)
    let min = values.min()!
    let max = values.max()!
    let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / Double(values.count)
    let stdDev = sqrt(variance)

    // Linear trend: slope via least squares
    let n = Double(values.count)
    let xMean = (n - 1) / 2
    let slope = zip(values.indices, values).map { (i, v) in
        (Double(i) - xMean) * (v - mean)
    }.reduce(0, +) / values.map { pow($0 - mean, 2) }.reduce(0, +).nonZero

    let trendDir: String
    let slopePerDay = slope / Double(max(days, 1))
    if abs(slopePerDay) < mean * 0.005 {
        trendDir = "stable"
    } else if slopePerDay > 0 {
        trendDir = metric == "resting_hr" || metric == "respiratory_rate" ? "worsening" : "improving"
    } else {
        trendDir = metric == "resting_hr" || metric == "respiratory_rate" ? "improving" : "declining"
    }

    return encode([
        "data_available": true,
        "metric": metric,
        "days_requested": days,
        "days_available": values.count,
        "mean": round(mean * 10) / 10,
        "min": round(min * 10) / 10,
        "max": round(max * 10) / 10,
        "std_dev": round(stdDev * 10) / 10,
        "trend_direction": trendDir,
        "trend_note": "Slope: \(String(format: "%.2f", slopePerDay)) per day over \(values.count) samples"
    ])
}

private func metricValue(entry: DayEntry, metric: String) -> Double? {
    switch metric {
    case "hrv":                return entry.hrv
    case "resting_hr":         return entry.restingHR
    case "respiratory_rate":   return entry.respiratoryRate
    case "sleep_hours":        return entry.sleepHours
    case "sleep_efficiency":   return entry.sleepEfficiency
    case "active_calories":    return entry.activeCalories
    case "steps":              return entry.steps.map(Double.init)
    default:                   return nil
    }
}
```

Add extension for safe division:
```swift
extension Double {
    var nonZero: Double { self == 0 ? 1 : self }
}
```

**`getBaseline`:**
```swift
private func getBaseline(input: [String: Any]) async -> String {
    let baselines = await trendStore.baselines
    let status = await trendStore.baselineStatus
    let metric = input["metric"] as? String ?? "all"

    var result: [String: Any] = [
        "baseline_status": status.description,
        "data_available": true
    ]

    if metric == "all" || metric == "hrv" {
        result["hrv_7day_avg"] = baselines.hrv7DayAvg ?? NSNull()
        result["hrv_30day_avg"] = baselines.hrv30DayAvg ?? NSNull()
    }
    if metric == "all" || metric == "resting_hr" {
        result["resting_hr_7day_avg"] = baselines.restingHR7DayAvg ?? NSNull()
        result["resting_hr_30day_avg"] = baselines.restingHR30DayAvg ?? NSNull()
    }
    if metric == "all" || metric == "sleep_hours" {
        result["sleep_hours_7day_avg"] = baselines.sleepHours7DayAvg ?? NSNull()
        result["sleep_hours_30day_avg"] = baselines.sleepHours30DayAvg ?? NSNull()
    }
    if metric == "all" || metric == "sleep_efficiency" {
        result["sleep_efficiency_30day_avg"] = baselines.sleepEfficiency30DayAvg ?? NSNull()
    }
    if metric == "all" || metric == "respiratory_rate" {
        result["respiratory_rate_30day_avg"] = baselines.respiratoryRate30DayAvg ?? NSNull()
    }
    return encode(result)
}
```

**`getGoalProgress`:**
```swift
private func getGoalProgress(input: [String: Any]) async -> String {
    let goals = await goalStore.goals
    let snapshots = await progressStore.weeklySnapshots

    guard !goals.isEmpty else {
        return encode(["data_available": false, "reason": "No active goals set."])
    }

    let metric = input["metric"] as? String ?? "all"
    let filtered = metric == "all" ? goals : goals.filter { $0.metric.rawValue == metric }

    let goalData: [[String: Any]] = filtered.map { goal in
        let goalSnaps = snapshots.filter { $0.goalId == goal.id }.sorted { $0.weekStart < $1.weekStart }
        let latest = goalSnaps.last

        var g: [String: Any] = [
            "id": goal.id.uuidString,
            "metric": goal.metric.label,
            "mode": goal.mode.rawValue,
            "baseline_at_set": goal.baselineAtSet,
            "current_phase": goal.currentPhase ?? 1
        ]
        if goal.mode == .target {
            g["target_value"] = goal.targetValue
            g["timeframe_weeks"] = goal.timeframeWeeks ?? NSNull()
            g["weeks_elapsed"] = goal.weeksElapsed
        }
        if let snap = latest {
            g["last_week_avg"] = snap.weekAvg
            g["last_week_pace"] = snap.pace
        }
        return g
    }

    return encode(["data_available": true, "goals": goalData])
}
```

**`getProtocols`:**
```swift
private func getProtocols(input: [String: Any]) async -> String {
    guard let conditions = input["conditions"] as? [String] else {
        return encodeError("conditions array is required")
    }
    let maxEffort = input["max_effort"] as? String

    let matched = protocolMatcher.matchByFlags(
        flags: Set(conditions),
        maxEffort: maxEffort
    )

    let protocols: [[String: Any]] = matched.map { p in [
        "id": p.id,
        "title": p.title,
        "description": p.protocolDescription,
        "effort": p.effort,
        "duration_minutes": p.durationMinutes ?? NSNull()
    ]}

    return encode(["data_available": true, "count": protocols.count, "protocols": protocols])
}
```

This requires adding a `matchByFlags(flags:maxEffort:)` method to `ProtocolMatcher` that takes a precomputed set of condition flags instead of re-evaluating health data. This makes the tool interface clean.

**`getCorrelation`:**
```swift
private func getCorrelation(input: [String: Any]) async -> String {
    guard let metricA = input["metric_a"] as? String,
          let metricB = input["metric_b"] as? String,
          let days = input["days"] as? Int else {
        return encodeError("metric_a, metric_b, and days are required")
    }

    let history = await trendStore.history
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let cutoff = formatter.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date())!)
    let window = history.filter { $0.date >= cutoff }

    // Collect paired samples (both metrics must be non-nil for same day)
    let pairs: [(Double, Double)] = window.compactMap { entry in
        guard let a = metricValue(entry: entry, metric: metricA),
              let b = metricValue(entry: entry, metric: metricB) else { return nil }
        return (a, b)
    }

    guard pairs.count >= 5 else {
        return encode([
            "data_available": false,
            "reason": "Insufficient paired data: \(pairs.count) days (need 5+)",
            "metric_a": metricA, "metric_b": metricB
        ])
    }

    let n = Double(pairs.count)
    let meanA = pairs.map(\.0).reduce(0, +) / n
    let meanB = pairs.map(\.1).reduce(0, +) / n
    let cov = pairs.map { ($0.0 - meanA) * ($0.1 - meanB) }.reduce(0, +) / n
    let stdA = sqrt(pairs.map { pow($0.0 - meanA, 2) }.reduce(0, +) / n)
    let stdB = sqrt(pairs.map { pow($0.1 - meanB, 2) }.reduce(0, +) / n)
    let pearson = (stdA * stdB) == 0 ? 0 : cov / (stdA * stdB)

    let direction: String
    if pearson > 0.3 { direction = "positive" }
    else if pearson < -0.3 { direction = "negative" }
    else { direction = "none" }

    // Show a few example data points for the LLM to reference
    let examples = pairs.prefix(5).map { ["a": $0.0, "b": $0.1] }

    return encode([
        "data_available": true,
        "metric_a": metricA, "metric_b": metricB,
        "sample_days": pairs.count,
        "pearson_r": round(pearson * 100) / 100,
        "direction": direction,
        "interpretation": direction == "none"
            ? "No meaningful correlation found."
            : "\(metricA) and \(metricB) show a \(direction) correlation (r=\(String(format: "%.2f", pearson)))",
        "example_pairs": examples
    ])
}
```

**Shared encode helpers:**
```swift
private func encode(_ dict: [String: Any]) -> String {
    guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
          let str = String(data: data, encoding: .utf8) else { return "{}" }
    return str
}

private func encodeError(_ message: String) -> String {
    encode(["error": message, "data_available": false])
}
```

---

### B-4. Add `matchByFlags` to `ProtocolMatcher`

In `ProtocolMatcher.swift`, add a public method that accepts precomputed flags:

```swift
func matchByFlags(flags: Set<String>, maxEffort: String? = nil) -> [WellnessProtocol] {
    let allProtocols = loadProtocols()
    var matched = allProtocols.filter { protocol in
        !protocol.conditions.isDisjoint(with: flags)
    }
    if let maxEffortStr = maxEffort {
        let effortMap = ["none": 0, "low": 1, "medium": 2, "high": 3]
        let maxVal = effortMap[maxEffortStr] ?? 5
        matched = matched.filter { $0.effort <= maxVal }
    }
    return Array(matched.prefix(5))
}
```

---

### B-5. Create `Services/AgentRunner.swift`

```swift
import Foundation

actor AgentRunner {
    private let client: AnthropicClient
    private let executor: ToolExecutor
    private let logStore: LLMInteractionStore
    private let maxIterations = 8

    init(client: AnthropicClient, executor: ToolExecutor, logStore: LLMInteractionStore) {
        self.client = client
        self.executor = executor
        self.logStore = logStore
    }

    func run(
        feature: LLMFeature,
        system: String,
        initialMessage: String,
        model: String,
        maxTokens: Int = 1024
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
                tools: AgentTools.definitions,
                model: model,
                maxTokens: maxTokens
            )
            totalInputTokens += response.usage.inputTokens ?? 0
            totalOutputTokens += response.usage.outputTokens ?? 0

            if response.toolCalls.isEmpty {
                // Final answer
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                let interaction = LLMInteraction(
                    id: UUID(), timestamp: startTime,
                    feature: feature, model: model,
                    systemPrompt: system,
                    messages: messages.map { LoggedMessage(from: $0) },
                    tools: AgentTools.definitions.compactMap { $0["name"] as? String },
                    rawResponse: response.text, parsedSuccessfully: true,
                    toolCallsMade: allToolCalls,
                    durationMs: duration,
                    inputTokens: totalInputTokens, outputTokens: totalOutputTokens,
                    iterationCount: iteration + 1
                )
                await logStore.record(interaction)
                return AgentResult(
                    text: response.text,
                    toolCallCount: allToolCalls.count,
                    toolsSummary: allToolCalls.map(\.toolName)
                )
            }

            // Append assistant turn with tool calls
            messages.append(["role": "assistant", "content": response.rawContent])

            // Execute tool calls and collect results
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
            messages.append(["role": "user", "content": toolResultBlocks])
        }

        throw AppError.agentMaxIterationsReached
    }
}

struct AgentResult {
    let text: String
    let toolCallCount: Int
    let toolsSummary: [String]
}
```

---

### B-6. Add Lean `ContextBuilder.buildAgentFrame()`

In `ContextBuilder.swift`, add alongside the existing methods (do not remove the old ones yet):

```swift
static func buildAgentFrame(
    baselineStatus: BaselineStatus,
    goalCount: Int,
    todayEvents: [String]
) -> String {
    let dateStr = Date().formatted(date: .complete, time: .shortened)
    let eventsStr = todayEvents.isEmpty ? "none" : todayEvents.joined(separator: ", ")
    return """
    === PULSE AGENT — \(dateStr) ===

    Baseline Status: \(baselineStatus.description)
    Active Goals: \(goalCount)
    Today's Reported Events: \(eventsStr)

    You have access to tools to investigate the user's health data.
    Use get_baseline and get_health_data before drawing conclusions.
    Do not claim trends without calling get_trend_stats first.
    """
}
```

---

### B-7. Feature Flag

Add to `UserDefaults` before migrating any feature:

```swift
// In a shared constants file or inline:
extension UserDefaults {
    var agenticModeEnabled: Bool {
        get { bool(forKey: "agenticModeEnabled") }
        set { set(newValue, forKey: "agenticModeEnabled") }
    }
}

// Default: false during rollout, flip to true when stable
```

---

### B-8. Migrate Chat (Step 1)

**File:** `Views/Chat/ChatViewModel.swift`

Add `AgentRunner` dependency. In `send()`, check the feature flag:

```swift
// Add to ChatViewModel
private var agentRunner: AgentRunner?

// In loadContext() or init, after stores are loaded:
// agentRunner = AgentRunner(client: client, executor: executor, logStore: logStore)

// In send():
func send(userText: String) async {
    // ... existing guard and message append ...

    if UserDefaults.standard.agenticModeEnabled, let runner = agentRunner {
        do {
            let baselineStatus = await trendStore?.baselineStatus ?? .cold
            let goalCount = await goalStore?.goals.count ?? 0
            let frame = ContextBuilder.buildAgentFrame(
                baselineStatus: baselineStatus,
                goalCount: goalCount,
                todayEvents: currentEvents
            )
            let result = try await runner.run(
                feature: .chat,
                system: Prompts.system,
                initialMessage: frame + "\n\nUser question: " + userText,
                model: /* analysis model for chat */
            )
            let reply = ChatMessage(role: .assistant, content: result.text, isUIOnly: false)
            messages.append(reply)
            if result.toolCallCount > 0 {
                // Store tool summary on the message for UI display
                lastToolSummary = "analyzed \(result.toolCallCount) data source\(result.toolCallCount == 1 ? "" : "s")"
            }
        } catch {
            // Fall through to existing completeChat path
        }
    } else {
        // existing completeChat path unchanged
    }
}
```

Add `@Published var lastToolSummary: String? = nil` to `ChatViewModel`.

In `MessageBubbleView.swift` or `ChatView.swift`, show the tool summary below the last assistant message:

```swift
// After the assistant bubble, if it's the last message:
if let summary = viewModel.lastToolSummary, message == viewModel.messages.last {
    Text("🔍 \(summary)")
        .font(.caption2)
        .foregroundStyle(.secondary)
        .padding(.leading, 12)
}
```

**Validate:** Chat works with agentic flag on. Tool calls appear in LLM Log. Responses reference data the LLM pulled via tools. Falls back to old path if runner throws.

---

### B-9. Migrate Weekly Review (Step 2)

**File:** `Views/Today/WeeklyReviewViewModel.swift`

Same pattern as Chat. The weekly review system prompt should gain an instruction:

Add to `Prompts.swift`:
```swift
static let weeklyReviewAgentInstruction = """
You are generating a weekly wellness coaching review.

REQUIRED: Before writing your assessment, you MUST call:
1. get_trend_stats for each active goal metric (7 days and 14 days)
2. get_baseline to understand personal context
3. get_goal_progress to see current phase and pace
4. get_health_data for the past 7 days to see daily patterns

After gathering data via tools, write your review as a JSON object following this schema:
[insert weeklyReviewInstruction JSON schema here]
"""
```

The weekly review `AgentRunner.run()` call uses `analysisModel` (Sonnet) with `maxTokens: 2048`.

---

### B-10. Migrate Morning Card (Step 3)

**File:** `Views/Today/TodayViewModel.swift`

`generateMorningCard()` calls `agentRunner.run()` instead of `client.completeMorningCard()`.

The morning card agent prompt instructs:
```swift
static let morningCardAgentInstruction = """
You are generating a morning readiness card.

REQUIRED: Start by calling get_baseline and get_health_data for today.
Then call get_protocols with the appropriate condition flags.

After gathering data, respond with ONLY a valid JSON object:
[insert existing morningCardInstruction JSON schema]
"""
```

---

### B-11. Phase B Validation Checklist

- [ ] `completeWithTools()` correctly parses `tool_use` content blocks
- [ ] `AgentRunner` loop terminates on `end_turn` (no tool calls)
- [ ] `AgentRunner` loop terminates after max 8 iterations with `agentMaxIterationsReached`
- [ ] Tool call inputs/outputs appear fully in LLM Log detail view
- [ ] Chat with agentic flag on answers "What was my HRV trend last 3 weeks?" correctly
- [ ] Weekly review references actual 7-day trend statistics from tool calls
- [ ] Morning card protocols match the corpus IDs (no invented IDs)
- [ ] Feature flag off → old behavior unchanged
- [ ] Feature flag on → tool calls visible in UI ("analyzed N data sources")
- [ ] Correlation tool returns reasonable results for HRV vs. alcohol

---

## Phase C: Long-Term Memory
**Estimated effort:** 1 week
**Risk:** Low-medium — memory is additive context; worst case is verbose responses

**Prerequisite:** Phase B complete and stable.

---

### C-1. Create Memory Model Types

New file: `Models/MemoryModels.swift`

```swift
import Foundation

struct EpisodicMemory: Identifiable, Codable {
    let id: String              // e.g. "mem_001"
    let date: String            // "yyyy-MM-dd"
    let type: EpisodicType
    let tags: [String]
    let content: String         // 1-3 sentences
    let source: LLMFeature
    let importance: MemoryImportance
}

enum EpisodicType: String, Codable {
    case observation, pattern, milestone, userStatement, anomaly
}

enum MemoryImportance: String, Codable, Comparable {
    case low, medium, high
    static func < (a: Self, b: Self) -> Bool {
        let order: [Self] = [.low, .medium, .high]
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }
}

struct PatternMemory: Identifiable, Codable {
    let id: String
    let metric: String
    let patternType: String      // "correlation" | "positive_driver" | "negative_driver"
    let description: String
    let confidence: MemoryConfidence
    let evidenceCount: Int
    let lastObserved: String     // "yyyy-MM-dd"
    let tags: [String]
}

enum MemoryConfidence: String, Codable {
    case low, medium, high
}

struct IdentitySummary: Codable {
    let lastUpdated: String
    let generatedBy: String
    let summary: String
    let keySensitivities: [String]
    let keyStrengths: [String]
    let activeFocus: String
}

struct MemoryContext {
    let identitySummary: String
    let recentEpisodic: [EpisodicMemory]    // top 5 high-importance + last 3 any
    let patterns: [PatternMemory]           // all high-confidence + relevant medium
}
```

---

### C-2. Create `Models/MemoryStore.swift`

```swift
import Foundation

actor MemoryStore {
    private var episodic: [EpisodicMemory] = []
    private var patterns: [PatternMemory] = []
    private var identitySummary: IdentitySummary?

    private let episodicURL: URL
    private let patternURL: URL
    private let identityURL: URL

    private let maxEpisodic = 60
    private let maxPatterns = 30

    private init(episodic: [EpisodicMemory], patterns: [PatternMemory],
                 identitySummary: IdentitySummary?,
                 episodicURL: URL, patternURL: URL, identityURL: URL) {
        self.episodic = episodic
        self.patterns = patterns
        self.identitySummary = identitySummary
        self.episodicURL = episodicURL
        self.patternURL = patternURL
        self.identityURL = identityURL
    }

    static func load() async -> MemoryStore {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let eURL = docs.appendingPathComponent("episodic_memory.json")
        let pURL = docs.appendingPathComponent("pattern_memory.json")
        let iURL = docs.appendingPathComponent("identity_summary.json")
        let decoder = JSONDecoder()
        let episodic = (try? decoder.decode([EpisodicMemory].self, from: Data(contentsOf: eURL))) ?? []
        let patterns = (try? decoder.decode([PatternMemory].self, from: Data(contentsOf: pURL))) ?? []
        let identity = try? decoder.decode(IdentitySummary.self, from: Data(contentsOf: iURL))
        return MemoryStore(episodic: episodic, patterns: patterns, identitySummary: identity,
                           episodicURL: eURL, patternURL: pURL, identityURL: iURL)
    }

    func writeEpisodic(_ entry: EpisodicMemory) throws {
        episodic.append(entry)
        pruneEpisodic()
        try save(episodic, to: episodicURL)
    }

    func writePattern(_ pattern: PatternMemory) throws {
        if let idx = patterns.firstIndex(where: { $0.id == pattern.id }) {
            patterns[idx] = pattern
        } else {
            patterns.append(pattern)
        }
        try save(patterns, to: patternURL)
    }

    func writeIdentitySummary(_ summary: IdentitySummary) throws {
        identitySummary = summary
        try save(summary, to: identityURL)
    }

    func buildMemoryContext(relevantTags: Set<String> = []) -> MemoryContext {
        // Episodic: last 5 high-importance + last 3 any (deduplicated)
        let highImportance = episodic.filter { $0.importance == .high }.suffix(5)
        let lastThree = episodic.suffix(3)
        var recentSet = Set(highImportance.map(\.id))
        var recent = Array(highImportance)
        for entry in lastThree where !recentSet.contains(entry.id) {
            recent.append(entry)
            recentSet.insert(entry.id)
        }

        // Patterns: all high-confidence + medium-confidence with relevant tags
        let relevantPatterns = patterns.filter {
            $0.confidence == .high || !Set($0.tags).isDisjoint(with: relevantTags)
        }

        return MemoryContext(
            identitySummary: identitySummary?.summary ?? "No long-term model built yet.",
            recentEpisodic: recent,
            patterns: relevantPatterns
        )
    }

    func pruneIfNeeded() throws {
        pruneEpisodic()
        if patterns.count > maxPatterns {
            patterns.sort { $0.confidence.rawValue > $1.confidence.rawValue }
            patterns = Array(patterns.prefix(maxPatterns))
            try save(patterns, to: patternURL)
        }
    }

    private func pruneEpisodic() {
        guard episodic.count > maxEpisodic else { return }
        // Remove oldest low-importance first
        let lowIndices = episodic.indices.filter { episodic[$0].importance == .low }
        let toRemove = episodic.count - maxEpisodic
        let removeIndices = Set(lowIndices.prefix(toRemove))
        episodic = episodic.enumerated()
            .filter { !removeIndices.contains($0.offset) }
            .map(\.element)
    }

    private func save<T: Codable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }
}
```

---

### C-3. Add `write_memory` and `write_identity_summary` Tools

In `AgentTools.swift`, add two tools to the `definitions` array:

```swift
// Tool 7: Write a memory entry
[
    "name": "write_memory",
    "description": """
        Store a notable observation, user statement, identified pattern, or milestone
        in long-term memory for recall in future sessions.
        Use for: significant biometric events, patterns you've confirmed across multiple
        data points, things the user explicitly told you, milestones reached, anomalous
        health periods. Do NOT write trivial daily observations.
        Only write what would be genuinely useful to recall in 2-4 weeks.
        """,
    "input_schema": [
        "type": "object",
        "required": ["type", "content", "tags", "importance"],
        "properties": [
            "type": [
                "type": "string",
                "enum": ["observation", "pattern", "milestone", "user_statement", "anomaly"]
            ],
            "content": ["type": "string", "description": "1-3 sentences describing the memory."],
            "tags": ["type": "array", "items": ["type": "string"]],
            "importance": ["type": "string", "enum": ["low", "medium", "high"]]
        ]
    ]
],

// Tool 8: Rewrite identity summary (weekly review only)
[
    "name": "write_identity_summary",
    "description": """
        Rewrite the persistent user identity summary. Called once per weekly review.
        Write 3-5 sentences in third person describing who this person is as a health
        subject: their current focus, active goal progress, key sensitivities, and
        what is working. This document is injected into every future agent session.
        """,
    "input_schema": [
        "type": "object",
        "required": ["summary", "key_sensitivities", "key_strengths", "active_focus"],
        "properties": [
            "summary": ["type": "string"],
            "key_sensitivities": ["type": "array", "items": ["type": "string"]],
            "key_strengths": ["type": "array", "items": ["type": "string"]],
            "active_focus": ["type": "string"]
        ]
    ]
]
```

For the non-weekly-review agent sessions, exclude `write_identity_summary` from the tool list. Create two sets:

```swift
static let standardDefinitions: [[String: Any]] = Array(definitions.prefix(7))  // tools 1-7
static let weeklyReviewDefinitions: [[String: Any]] = definitions                 // all 8
```

---

### C-4. Add Memory Handling to `ToolExecutor`

Add `MemoryStore` reference:

```swift
actor ToolExecutor {
    // ... existing properties ...
    private let memoryStore: MemoryStore    // ADD

    init(trendStore: TrendStore, goalStore: GoalStore, progressStore: ProgressStore, memoryStore: MemoryStore) {
        // ...
        self.memoryStore = memoryStore
    }

    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        // ... existing cases ...
        case "write_memory":            return await writeMemory(input: input)
        case "write_identity_summary":  return await writeIdentitySummary(input: input)
        default:
            return encodeError("Unknown tool: \(name)")
        }
    }
}
```

**Implement write tools:**

```swift
private func writeMemory(input: [String: Any]) async -> String {
    guard let typeStr = input["type"] as? String,
          let content = input["content"] as? String,
          let tags = input["tags"] as? [String],
          let importanceStr = input["importance"] as? String else {
        return encodeError("Missing required fields: type, content, tags, importance")
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"
    let today = formatter.string(from: Date())

    let entry = EpisodicMemory(
        id: "mem_\(UUID().uuidString.prefix(8))",
        date: today,
        type: EpisodicType(rawValue: typeStr) ?? .observation,
        tags: tags,
        content: content,
        source: .agentLoop,    // caller context — you could pass feature through ToolExecutor
        importance: MemoryImportance(rawValue: importanceStr) ?? .medium
    )

    do {
        try await memoryStore.writeEpisodic(entry)
        return encode(["success": true, "id": entry.id])
    } catch {
        return encodeError("Failed to write memory: \(error.localizedDescription)")
    }
}

private func writeIdentitySummary(input: [String: Any]) async -> String {
    guard let summary = input["summary"] as? String,
          let sensitivities = input["key_sensitivities"] as? [String],
          let strengths = input["key_strengths"] as? [String],
          let focus = input["active_focus"] as? String else {
        return encodeError("Missing required fields")
    }

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd"

    let identitySummary = IdentitySummary(
        lastUpdated: formatter.string(from: Date()),
        generatedBy: "weekly_review",
        summary: summary,
        keySensitivities: sensitivities,
        keyStrengths: strengths,
        activeFocus: focus
    )

    do {
        try await memoryStore.writeIdentitySummary(identitySummary)
        return encode(["success": true])
    } catch {
        return encodeError("Failed to write identity summary: \(error.localizedDescription)")
    }
}
```

---

### C-5. Update `ContextBuilder.buildAgentFrame()` to Include Memory

```swift
static func buildAgentFrame(
    baselineStatus: BaselineStatus,
    goalCount: Int,
    todayEvents: [String],
    memory: MemoryContext
) -> String {
    let dateStr = Date().formatted(date: .complete, time: .shortened)
    let eventsStr = todayEvents.isEmpty ? "none" : todayEvents.joined(separator: ", ")

    var sections: [String] = [
        "=== PULSE AGENT — \(dateStr) ===",
        "",
        "Baseline Status: \(baselineStatus.description)",
        "Active Goals: \(goalCount)",
        "Today's Reported Events: \(eventsStr)",
    ]

    // Identity summary (always injected)
    sections += [
        "",
        "=== WHAT I KNOW ABOUT YOU ===",
        memory.identitySummary
    ]

    // Recent episodic memories (if any)
    if !memory.recentEpisodic.isEmpty {
        sections.append("")
        sections.append("=== RECENT NOTABLE EVENTS ===")
        for entry in memory.recentEpisodic {
            sections.append("[\(entry.date)] \(entry.content)")
        }
    }

    // Patterns (if any)
    if !memory.patterns.isEmpty {
        sections.append("")
        sections.append("=== YOUR PATTERNS ===")
        for pattern in memory.patterns {
            sections.append("- \(pattern.description)")
        }
    }

    sections += [
        "",
        "You have tools to investigate data. Use get_baseline and get_health_data",
        "before drawing conclusions. Do not claim trends without calling get_trend_stats first."
    ]

    return sections.joined(separator: "\n")
}
```

Update all `AgentRunner.run()` call sites to pass `memory: MemoryContext` from `memoryStore.buildMemoryContext()`.

---

### C-6. Weekly Review Identity Summary Rewrite

In the weekly review agent prompt, append after the JSON schema instruction:

```swift
// In Prompts.swift
static let weeklyReviewAgentInstruction = """
[existing weekly review JSON schema instruction]

After completing your JSON output, call write_identity_summary to update the
persistent user model. Rewrite it based on everything you've observed this week
plus the existing patterns. Write 3-5 sentences in third person.
"""
```

Pass `weeklyReviewDefinitions` (all 8 tools) to the weekly review `AgentRunner.run()` call.

---

### C-7. Memory Pruning on App Open

In `TodayViewModel.bootstrap()`, after loading all stores:

```swift
// After TrendStore, GoalStore, ProgressStore are loaded:
Task {
    try? await memoryStore.pruneIfNeeded()
}
```

---

### C-8. Phase C Validation Checklist

- [ ] `episodic_memory.json` created in Documents after first `write_memory` call
- [ ] `pattern_memory.json` created after first pattern write
- [ ] `identity_summary.json` created after first weekly review run
- [ ] Memory context appears in LLM Log detail (visible in system prompt / agent frame)
- [ ] Agent references past events in responses (e.g., "similar to March 3rd when you had high stress")
- [ ] Weekly review rewrites identity summary — verify by checking `identity_summary.json` after Sunday review
- [ ] `write_memory` tool is NOT available to the weekly review agent (only `write_identity_summary`)
  - Actually: `write_memory` IS available to all agents; `write_identity_summary` is weekly-review-only
- [ ] Memory injection stays under 400 tokens (check in LLM Log — input token count)
- [ ] Pruning works: create 70 episodic entries → verify count stays at 60 after prune
- [ ] Non-Sunday agent sessions do NOT call `write_identity_summary` (not in tool list)

---

## Cross-Cutting Decisions

### Token Budget

| Phase | Estimated additional tokens per call |
|---|---|
| A (logging) | 0 — logging only, no prompt change |
| B (agent frame) | +200–400 (lean frame replaces full context block) |
| B (per tool call) | +100–300 per round-trip (input + output per tool) |
| C (memory injection) | +200–400 (identity + top episodic + patterns) |

The agentic morning card may use 3–4 iterations × ~600 tokens each = ~2400 tokens vs. the current ~900 token single-shot. This is acceptable for a personal app with no cost constraints beyond the API key.

### Feature Flag Strategy

Use `UserDefaults` boolean flags during rollout:
- `agenticModeEnabled` — master flag (default: false during development, true when stable)
- Per-feature flags if needed: `agenticChat`, `agenticWeeklyReview`, `agenticMorningCard`

Remove feature flags once all three features are stable — don't leave dead code paths permanently.

### Error Handling Rules

| Error | Behavior |
|---|---|
| `agentMaxIterationsReached` | Show user-friendly message: "Try a more specific question" |
| Tool executor error | Return `{"error": "...", "data_available": false}` — never throw; let LLM handle gracefully |
| `write_memory` failure | Log to console, swallow — non-critical; don't show user |
| Memory load failure | Start with empty memory — app continues normally |

### Testing Strategy for Tool Implementations

Before wiring up `AgentRunner`, unit test each `ToolExecutor` method directly:

1. Load a real `TrendStore` from a test `Documents/trend_store.json`
2. Call each tool with valid and invalid inputs
3. Verify JSON output matches the documented schema
4. Verify error cases return `data_available: false` with a `reason` field

---

## File Creation Summary

| Phase | New Files | Modified Files |
|---|---|---|
| A | `Models/LLMInteractionLog.swift` | `Models/AppError.swift` |
| A | `Models/LLMInteractionStore.swift` | `Services/AnthropicClient.swift` |
| A | `Views/Settings/LLMLogView.swift` | `App/ContentView.swift` (log access) |
| B | `Services/AgentTools.swift` | `Services/AnthropicClient.swift` |
| B | `Services/ToolExecutor.swift` | `Services/ContextBuilder.swift` |
| B | `Services/AgentRunner.swift` | `Services/ProtocolMatcher.swift` |
| B | — | `Services/Prompts.swift` |
| B | — | `Views/Chat/ChatViewModel.swift` |
| B | — | `Views/Today/WeeklyReviewViewModel.swift` |
| B | — | `Views/Today/TodayViewModel.swift` |
| C | `Models/MemoryModels.swift` | `Services/AgentTools.swift` |
| C | `Models/MemoryStore.swift` | `Services/ToolExecutor.swift` |
| C | — | `Services/ContextBuilder.swift` |
| C | — | `Views/Today/TodayViewModel.swift` |
| C | — | `Services/Prompts.swift` |

**Total:** 7 new files, 11 modified files.
