# Pulse — Agentic Architecture Transition Roadmap
## From Context-Push to Tool-Pull + Long-Term Memory

---

## Current State Assessment

### What's Built (v1.0)

The current implementation is a well-structured **context-push** architecture:

- `ContextBuilder` pre-packages everything the LLM might need into a single large text block
- `AnthropicClient` makes single-shot completions — one request, one response, done
- Protocol matching is done in Swift (`ProtocolMatcher`) before the LLM ever sees the data
- Chat has conversation history but no tool access — the LLM can only reason on what was pre-loaded
- All feature calls (`completeMorningCard`, `completeCheckIn`, `completeWeeklyReview`, `completeChat`) are separate, isolated methods with no shared reasoning loop

### What This Architecture Cannot Do Well

| Limitation | Symptom |
|---|---|
| Context builder must anticipate every possible question | Chat answers are bounded by what was pre-loaded at `send()` time |
| LLM cannot request more data if it needs it | Complex trend questions get shallow answers |
| No visibility into what the LLM received or reasoned | Debugging requires log inspection, not in-app transparency |
| No memory across sessions | Every session starts from scratch — no cumulative understanding of the user |
| Insights discovered in one session are lost | Weekly review cannot build on previous weeks' coaching observations |
| LLM cannot correlate across multiple time windows dynamically | "Why has my HRV been declining for 3 weeks?" requires pre-packaged 21-day context |

---

## Target State

Three compounding upgrades, delivered in sequence:

```
Phase A: Observability        — see what the LLM sends and receives
Phase B: Agentic Loop         — LLM pulls data via tools instead of receiving pre-packaged context  
Phase C: Long-Term Memory     — LLM builds and recalls a persistent model of the user over time
```

Each phase is independently valuable and does not require the next to be useful. Ship each one before starting the next.

---

## Phase A: LLM Interaction Log
### "Show me everything"

**Scope:** Purely additive. No changes to existing LLM calls or architecture. Add an observation layer.

**Why first:** Before changing the architecture, you need full visibility into what's actually being sent and received. This also becomes the primary debugging tool for Phases B and C.

---

### A.1 LLMInteractionLog Model

New file: `Models/LLMInteractionLog.swift`

```swift
struct LLMInteraction: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let feature: LLMFeature
    let model: String
    
    // What was sent
    let systemPrompt: String
    let messages: [LoggedMessage]     // full messages array including injected context
    let tools: [String]?              // tool names if agentic (Phase B)
    
    // What was received
    let rawResponse: String           // exact text from API before any parsing
    let parsedSuccessfully: Bool
    let toolCallsMade: [LoggedToolCall]?   // populated in Phase B
    
    // Metadata
    let durationMs: Int
    let inputTokens: Int?             // from API usage field
    let outputTokens: Int?
    let iterationCount: Int           // 1 for single-shot, N for agentic loop
}

struct LoggedMessage: Codable {
    let role: String                  // "user" | "assistant"  
    let content: String               // full content including injected health context
    let isInjectedContext: Bool       // true for the system-injected health block
}

struct LoggedToolCall: Codable {
    let toolName: String
    let input: String                 // JSON string of inputs
    let output: String                // JSON string of result
    let durationMs: Int
}

enum LLMFeature: String, Codable, CaseIterable {
    case morningCard = "Morning Card"
    case checkIn = "Mid-Day Check-In"
    case weeklyReview = "Weekly Review"
    case chat = "Chat"
    case agentLoop = "Agent Loop"     // Phase B
}
```

---

### A.2 LLMInteractionStore

New file: `Models/LLMInteractionStore.swift`

Actor-based, persists to `Documents/llm_log.json`.

```swift
actor LLMInteractionStore {
    private var interactions: [LLMInteraction] = []
    private let fileURL: URL
    private let maxRetained: Int = 200    // keep last 200 interactions
    
    func record(_ interaction: LLMInteraction) async {
        interactions.append(interaction)
        if interactions.count > maxRetained {
            interactions.removeFirst(interactions.count - maxRetained)
        }
        try? await save()
    }
    
    func recent(limit: Int = 50) -> [LLMInteraction] {
        Array(interactions.suffix(limit).reversed())
    }
    
    func forFeature(_ feature: LLMFeature) -> [LLMInteraction] {
        interactions.filter { $0.feature == feature }.reversed()
    }
}
```

**Storage:** `llm_log.json` in Documents. Cap at 200 entries. Oldest entries pruned automatically.

---

### A.3 AnthropicClient — Instrumented Wrapper

Wrap every API call in a timing + logging block. The `AnthropicClient` actor gains a reference to `LLMInteractionStore`:

```swift
// In AnthropicClient, wrap every completion call:
private func instrumentedComplete(
    feature: LLMFeature,
    system: String,
    messages: [[String: Any]],
    model: String,
    maxTokens: Int
) async throws -> String {
    let start = Date()
    
    // Build the interaction record (pre-call)
    var interaction = LLMInteraction(
        id: UUID(),
        timestamp: start,
        feature: feature,
        model: model,
        systemPrompt: system,
        messages: messages.map { LoggedMessage(from: $0) },
        tools: nil,
        rawResponse: "",
        parsedSuccessfully: false,
        toolCallsMade: nil,
        durationMs: 0,
        inputTokens: nil,
        outputTokens: nil,
        iterationCount: 1
    )
    
    do {
        let result = try await rawComplete(system: system, messages: messages, model: model, maxTokens: maxTokens)
        let duration = Int(Date().timeIntervalSince(start) * 1000)
        
        interaction.rawResponse = result.text
        interaction.parsedSuccessfully = true
        interaction.durationMs = duration
        interaction.inputTokens = result.usage?.inputTokens
        interaction.outputTokens = result.usage?.outputTokens
        
        await logStore.record(interaction)
        return result.text
        
    } catch {
        interaction.rawResponse = "ERROR: \(error.localizedDescription)"
        interaction.durationMs = Int(Date().timeIntervalSince(start) * 1000)
        await logStore.record(interaction)
        throw error
    }
}
```

---

### A.4 LLM Log UI

New tab or settings-accessible debug panel. **This is a developer/power-user view** — accessible via a long-press on the app icon or a hidden gesture (e.g., triple-tap on version number in settings).

**Structure:**

```
LLM Log
├── Filter: [All] [Morning Card] [Check-In] [Weekly Review] [Chat]
└── List of interactions (newest first):
    ├── [Morning Card] Today 7:32 AM — haiku — 847ms — 312 in / 89 out tokens ✓
    ├── [Chat] Today 9:14 AM — sonnet — 1,204ms — 891 in / 156 out tokens ✓
    └── [Morning Card] Yesterday 7:41 AM — haiku — 923ms — 304 in / 91 out tokens ✓
```

**Interaction Detail View** (tap any row):

```
MORNING CARD — March 3, 2026 · 7:32 AM
Model: claude-haiku-4-5-20251001
Duration: 847ms · 312 → 89 tokens · Parsed: ✓

──── SYSTEM PROMPT ────────────────────────────────
[full system prompt text, monospaced, scrollable]

──── MESSAGES SENT ────────────────────────────────
[user]
=== HEALTH SUMMARY — Tuesday, March 3, 2026 ===
Baseline Status: established (34 days)
...
[full injected context block]
...
=== MODE ===
morning_card

──── RAW RESPONSE ─────────────────────────────────
{
  "readiness_level": "medium",
  "headline": "Solid recovery — moderate focus day",
  ...
}

──── PARSED OUTPUT ────────────────────────────────
Readiness: medium
Headline: Solid recovery — moderate focus day
...
```

**Share button** on the detail view — exports the full interaction as a `.txt` file. Useful for debugging prompt issues with Claude Code.

---

### A.5 What to Add to CLAUDE.md (Phase A)

```markdown
## LLM Interaction Log

Every LLM call is recorded to `LLMInteractionStore` (persists to `llm_log.json`).
Log entries include: full system prompt, full messages array with injected context,
raw API response, parse success, duration, token counts.

Access via: triple-tap on version number in Settings → LLM Log.
Use `logStore.recent()` for last N interactions.
Use `logStore.forFeature(.morningCard)` for feature-specific debugging.

When debugging a prompt issue:
1. Open LLM Log → find the failing interaction
2. Export as .txt
3. Paste into Anthropic Console to reproduce and iterate
```

---

## Phase B: Agentic Tool Loop
### "The LLM decides what it needs"

**Prerequisite:** Phase A complete. Log visibility is essential for debugging the agentic loop.

**Scope:** Add `AgentRunner` and `ToolExecutor`. Migrate Chat and Morning Card to tool-use. Keep Check-In as single-shot (speed matters there).

---

### B.1 What Changes, What Stays

| Component | Change |
|---|---|
| `AnthropicClient` | Add tool-use API support (parse `tool_use` content blocks) |
| `AgentRunner` | New actor — manages the multi-turn tool loop |
| `ToolExecutor` | New actor — dispatches tool calls to Swift implementations |
| `ContextBuilder` | Becomes thinner — provides only a lean initial frame |
| `ProtocolMatcher` | Becomes a tool the LLM calls, not pre-execution |
| `ChatViewModel` | Migrates to `AgentRunner.run()` instead of `AnthropicClient.completeChat()` |
| `TodayViewModel` | Morning card migrates to `AgentRunner.run()` |
| `CheckInResponse` | Stays as single-shot — latency is more important than depth here |
| `WeeklyReviewViewModel` | Migrates to `AgentRunner.run()` — most benefit from tool access |
| All JSON stores | No changes — they become tool data sources |

---

### B.2 Tool Definitions

Six tools. Defined as a static constant — never constructed dynamically.

```swift
// Services/AgentTools.swift

static let definitions: [[String: Any]] = [
    
    // Tool 1: Health data for a date or date range
    [
        "name": "get_health_data",
        "description": """
            Retrieve health metrics for a specific date or date range.
            Returns HRV, resting HR, sleep hours, sleep efficiency, 
            respiratory rate, active calories, steps, alcohol reported, 
            and subjective events logged.
            Use days_back for trend queries. Use date for a specific day.
            """,
        "input_schema": [
            "type": "object",
            "properties": [
                "date": [
                    "type": "string",
                    "description": "ISO date (YYYY-MM-DD), or 'today', 'yesterday'"
                ],
                "days_back": [
                    "type": "integer",
                    "description": "Number of days back from today. Max 90. Use for trends."
                ]
            ]
        ]
    ],
    
    // Tool 2: Computed trend statistics
    [
        "name": "get_trend_stats",
        "description": """
            Compute statistical summary for a metric over a time window.
            Returns mean, min, max, standard deviation, and trend direction 
            (improving / declining / stable). Use this before concluding 
            a metric is trending in a direction.
            """,
        "input_schema": [
            "type": "object",
            "required": ["metric", "days"],
            "properties": [
                "metric": [
                    "type": "string",
                    "enum": ["hrv", "resting_hr", "respiratory_rate", 
                             "sleep_hours", "sleep_efficiency", 
                             "active_calories", "steps"]
                ],
                "days": [
                    "type": "integer",
                    "description": "Window size in days. Common values: 7, 14, 30."
                ]
            ]
        ]
    ],
    
    // Tool 3: Personal baseline values
    [
        "name": "get_baseline",
        "description": """
            Get the user's personal baseline values and baseline status.
            Always call this before making comparisons — never assume 
            what is 'normal' for this person without checking.
            """,
        "input_schema": [
            "type": "object",
            "properties": [
                "metric": [
                    "type": "string",
                    "enum": ["all", "hrv", "resting_hr", "respiratory_rate",
                             "sleep_hours", "sleep_efficiency"]
                ]
            ]
        ]
    ],
    
    // Tool 4: Goal status and progress
    [
        "name": "get_goal_progress",
        "description": """
            Get goal definitions, targets, phase information, weekly snapshots,
            pace assessment, and projected completion for active goals.
            Use this when the user asks about goals or progress.
            """,
        "input_schema": [
            "type": "object",
            "properties": [
                "metric": [
                    "type": "string",
                    "enum": ["all", "hrv", "resting_hr", "respiratory_rate"]
                ]
            ]
        ]
    ],
    
    // Tool 5: Protocol retrieval
    [
        "name": "get_protocols",
        "description": """
            Retrieve evidence-based Huberman Lab protocols relevant to 
            specific conditions. Returns protocol title, steps, duration, 
            effort level, and rationale. Use max_effort 'low' or 'none' 
            on low-readiness days.
            """,
        "input_schema": [
            "type": "object",
            "required": ["conditions"],
            "properties": [
                "conditions": [
                    "type": "array",
                    "items": ["type": "string"],
                    "description": """
                        Condition flags: low_hrv, very_low_hrv, elevated_rhr, 
                        poor_sleep, elevated_respiratory_rate, high_stress, 
                        possible_illness, well_recovered, peak_readiness
                        """
                ],
                "max_effort": [
                    "type": "string",
                    "enum": ["none", "low", "medium", "high"]
                ]
            ]
        ]
    ],
    
    // Tool 6: Correlation check between two metrics
    [
        "name": "get_correlation",
        "description": """
            Check whether two metrics show correlated patterns over a time window.
            Returns correlation direction (positive/negative/none) and 
            example data points. Use when investigating what might be 
            driving changes in an outcome metric.
            """,
        "input_schema": [
            "type": "object",
            "required": ["metric_a", "metric_b", "days"],
            "properties": [
                "metric_a": ["type": "string"],
                "metric_b": ["type": "string"],
                "days": ["type": "integer"]
            ]
        ]
    ]
]
```

---

### B.3 AgentRunner

```swift
// Services/AgentRunner.swift

actor AgentRunner {
    private let client: AnthropicClient
    private let executor: ToolExecutor
    private let logStore: LLMInteractionStore
    private let maxIterations = 8
    
    func run(
        feature: LLMFeature,
        system: String,
        initialMessage: String,
        model: String,
        maxTokens: Int = 1024
    ) async throws -> AgentResult {
        
        var messages: [[String: Any]] = [
            ["role": "user", "content": initialMessage]
        ]
        var allToolCalls: [LoggedToolCall] = []
        let startTime = Date()
        var iterationCount = 0
        
        for _ in 0..<maxIterations {
            iterationCount += 1
            
            let response = try await client.completeWithTools(
                system: system,
                messages: messages,
                tools: AgentTools.definitions,
                model: model,
                maxTokens: maxTokens
            )
            
            // No tool calls — final answer reached
            if response.toolCalls.isEmpty {
                let duration = Int(Date().timeIntervalSince(startTime) * 1000)
                
                // Log the full agent run
                let interaction = LLMInteraction(
                    feature: feature,
                    model: model,
                    systemPrompt: system,
                    messages: messages.map { LoggedMessage(from: $0) },
                    tools: AgentTools.definitions.compactMap { $0["name"] as? String },
                    rawResponse: response.text,
                    parsedSuccessfully: true,
                    toolCallsMade: allToolCalls,
                    durationMs: duration,
                    inputTokens: response.usage?.inputTokens,
                    outputTokens: response.usage?.outputTokens,
                    iterationCount: iterationCount
                )
                await logStore.record(interaction)
                
                return AgentResult(
                    text: response.text,
                    toolCallCount: allToolCalls.count,
                    toolsSummary: allToolCalls.map { $0.toolName }
                )
            }
            
            // Append assistant turn (with tool calls)
            messages.append(["role": "assistant", "content": response.rawContent])
            
            // Execute all requested tool calls
            var toolResults: [[String: Any]] = []
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
                
                toolResults.append([
                    "type": "tool_result",
                    "tool_use_id": call.id,
                    "content": result
                ])
            }
            
            // Append tool results, continue loop
            messages.append(["role": "user", "content": toolResults])
        }
        
        throw AppError.agentMaxIterationsReached
    }
}

struct AgentResult {
    let text: String
    let toolCallCount: Int
    let toolsSummary: [String]    // for UI display: "analyzed 4 data sources"
}
```

---

### B.4 ToolExecutor

```swift
// Services/ToolExecutor.swift

actor ToolExecutor {
    private let healthKitManager: HealthKitManager
    private let trendStore: TrendStore
    private let goalStore: GoalStore
    private let progressStore: ProgressStore
    private let protocolMatcher: ProtocolMatcher
    
    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        case "get_health_data":        return await healthData(input: input)
        case "get_trend_stats":        return await trendStats(input: input)
        case "get_baseline":           return await baseline(input: input)
        case "get_goal_progress":      return await goalProgress(input: input)
        case "get_protocols":          return await protocols(input: input)
        case "get_correlation":        return await correlation(input: input)
        default:
            return "{\"error\": \"Unknown tool: \(name)\"}"
        }
    }
    
    // Each private method queries the relevant store and returns JSON string.
    // Returns "{\"error\": \"...\"}" on failure — never throws.
    // The LLM handles errors gracefully when tool results contain error fields.
    
    private func healthData(input: [String: Any]) async -> String {
        // Parse date or days_back from input
        // Query trendStore.history for the requested window
        // Return as JSON array of DayEntry objects
    }
    
    private func trendStats(input: [String: Any]) async -> String {
        // Extract metric + days
        // Compute mean, min, max, stdDev, trend direction from history
        // Trend direction: linear regression slope sign over the window
    }
    
    private func correlation(input: [String: Any]) async -> String {
        // Extract metric_a, metric_b, days
        // Compute Pearson correlation coefficient from history
        // Return: coefficient, direction, sample_size, example data points
    }
    
    // ... other methods
}
```

**Tool result format** — always JSON string, always includes a `data_available` flag:

```json
{
  "data_available": true,
  "metric": "hrv",
  "days_requested": 21,
  "days_available": 21,
  "mean": 60.4,
  "min": 44.0,
  "max": 71.0,
  "std_dev": 6.2,
  "trend_direction": "stable",
  "trend_note": "No significant change over 21 days (slope: +0.1ms/day)"
}
```

---

### B.5 Lean Initial Context

`ContextBuilder` becomes a thin frame — just enough for the LLM to orient itself:

```swift
static func buildAgentFrame(
    summary: HealthSummary,
    baselineStatus: BaselineStatus,
    goalCount: Int,
    todayEvents: [String]
) -> String {
    """
    === PULSE AGENT — \(Date().formatted(date: .complete, time: .shortened)) ===
    
    Baseline Status: \(baselineStatus.description)
    Active Goals: \(goalCount)
    Today's Reported Events: \(todayEvents.isEmpty ? "none" : todayEvents.joined(separator: ", "))
    
    You have access to the following tools to investigate the user's data:
    - get_health_data: query specific dates or date ranges
    - get_trend_stats: compute statistical trends for any metric
    - get_baseline: retrieve personal baseline values
    - get_goal_progress: get goal targets, phases, and weekly progress
    - get_protocols: retrieve relevant Huberman protocols
    - get_correlation: check relationships between two metrics
    
    Use tools to investigate before drawing conclusions. 
    Do not make claims about trends without calling get_trend_stats first.
    """
}
```

The old `ContextBuilder.buildMorningCardContext()` and `buildChatContext()` are kept for now as fallbacks but no longer used by migrated features.

---

### B.6 Migration Order

Migrate features one at a time. Test each before migrating the next.

**Step 1 — Chat** (lowest risk, most benefit)
- `ChatViewModel.send()` calls `agentRunner.run(feature: .chat, ...)` instead of `client.completeChat()`
- Result is `agentResult.text` — same as before for the UI
- Show `"analyzed \(agentResult.toolCallCount) data sources"` below agent responses
- Keep old `completeChat()` path behind a feature flag for fallback

**Step 2 — Weekly Review** (highest complexity benefit)
- `WeeklyReviewViewModel.generate()` uses agent loop
- The weekly review system prompt explicitly instructs: "You must call get_trend_stats for each active goal metric before writing your assessment."
- This produces dramatically better week-over-week analysis

**Step 3 — Morning Card** (highest frequency)
- Migrate last — most tested feature, most visible if something breaks
- Morning card system prompt instructs: "Start by calling get_baseline and get_health_data for today before determining readiness level."

**Do not migrate Check-In** — keep as single-shot. The check-in is time-sensitive (user is mid-day, wants a quick answer) and the pre-packaged context is sufficient for its narrow purpose.

---

### B.7 UI: Tool Call Transparency

Two levels of transparency in the UI:

**Inline indicator** (visible to user in normal use):
```
[assistant bubble]
Your HRV has been steadily building since week 2...

   🔍 analyzed 4 data sources  ←── subtle, tappable
```

Tapping "analyzed 4 data sources" expands an inline panel showing:
```
Data sources checked:
  ✓ get_baseline (HRV, resting_hr)         12ms
  ✓ get_health_data (last 21 days)          8ms
  ✓ get_trend_stats (hrv, 21 days)          6ms
  ✓ get_protocols (well_recovered, hrv)     4ms
```

**LLM Log** (full detail, developer view from Phase A):
Tool calls are now logged with `toolCallsMade` populated — inputs and outputs fully visible.

---

### B.8 Updated CLAUDE.md (Phase B additions)

```markdown
## Agentic Architecture

Chat, Morning Card, and Weekly Review use AgentRunner (max 8 iterations).
Check-In remains single-shot via AnthropicClient directly.

Tool call flow:
  AgentRunner.run() → AnthropicClient.completeWithTools()
  → ToolExecutor.execute() → Store/HealthKit queries
  → back to AnthropicClient → repeat until no tool calls → return text

ContextBuilder.buildAgentFrame() provides lean orientation only.
The LLM is responsible for pulling the data it needs via tools.

All agent runs are logged to LLMInteractionStore with full tool call trace.
Feature flag: Settings > Developer > Use Agentic Mode (default: on)
```

---

## Phase C: Long-Term Memory
### "The LLM knows you"

**Prerequisite:** Phase B complete. The agentic loop must be stable before adding memory.

**Scope:** A persistent memory store that accumulates observations across sessions, is summarized periodically, and is injected into every agent frame. The LLM both reads and writes to it.

---

### C.1 The Core Problem

Every Pulse session currently starts from zero. The LLM sees today's data and recent history — but has no recollection of:
- "Three weeks ago you had a bad HRV week — you mentioned travel was stressful"
- "Your HRV consistently drops when you report alcohol even just once"
- "You tend to sleep better on days with high step counts above 9,000"
- "Your respiratory rate elevated for 5 days in February — you had a cold"
- "Your best HRV weeks correlate with Zone 2 training 3x that week"

This is the difference between a generic wellness tool and something that actually knows you.

---

### C.2 Memory Architecture

Three tiers of memory, each with different lifespans and update frequencies:

```
Tier 1: Episodic Memory       — notable events and observations (rolling ~60 entries)
Tier 2: Pattern Memory        — learned correlations and tendencies (up to 30 patterns)  
Tier 3: Identity Summary      — compressed user model (single document, rewritten weekly)
```

All three are JSON files. No vector database. No embeddings. Simple retrieval by recency and relevance tags.

---

### C.3 Memory Store Files

**`Documents/episodic_memory.json`**
```json
{
  "entries": [
    {
      "id": "mem_001",
      "date": "2026-03-03",
      "type": "observation",
      "tags": ["hrv", "stress", "work"],
      "content": "HRV dropped to 44ms — 24% below 7-day baseline. User reported high stress. Combined with elevated RHR (58bpm). Suggested physiological sigh and no alcohol tonight.",
      "source": "morning_card",
      "importance": "high"
    },
    {
      "id": "mem_002", 
      "date": "2026-02-28",
      "type": "milestone",
      "tags": ["goal", "hrv", "phase_advance"],
      "content": "HRV goal Phase 1 completed early (week 3 of 3). 7-day avg reached 61.2ms — above Phase 1 sub-target of 60.5ms for 2 consecutive weeks. Entering Phase 2: Build.",
      "source": "weekly_review",
      "importance": "high"
    },
    {
      "id": "mem_003",
      "date": "2026-02-25",
      "type": "user_statement",
      "tags": ["travel", "sleep", "context"],
      "content": "User mentioned upcoming work travel next week. Anticipating sleep disruption.",
      "source": "chat",
      "importance": "medium"
    }
  ]
}
```

**`Documents/pattern_memory.json`**
```json
{
  "patterns": [
    {
      "id": "pat_001",
      "metric": "hrv",
      "pattern_type": "correlation",
      "description": "HRV drops 15-25% on nights following alcohol — consistently observed across 6 separate incidents.",
      "confidence": "high",
      "evidence_count": 6,
      "last_observed": "2026-03-01",
      "tags": ["hrv", "alcohol"]
    },
    {
      "id": "pat_002",
      "metric": "hrv",
      "pattern_type": "positive_driver",
      "description": "HRV improves on weeks with 3+ Zone 2 sessions (inferred from high active calorie days without HRV spike — suggests aerobic, not HIIT).",
      "confidence": "medium",
      "evidence_count": 3,
      "last_observed": "2026-02-28",
      "tags": ["hrv", "zone2", "training"]
    }
  ]
}
```

**`Documents/identity_summary.json`**
```json
{
  "last_updated": "2026-03-02",
  "generated_by": "weekly_review",
  "summary": "Mustafa is in week 4 of a 12-week HRV improvement goal (target: 70ms, current baseline: 61ms — ahead of pace). He responds well to Zone 2 training and is sensitive to alcohol, which consistently suppresses his HRV 15-25%. Sleep quality is his strongest metric — consistently above his baseline. His main vulnerability is work stress, which he reports occasionally and which correlates with HRV drops. He has been building consistent morning routines. His respiratory rate is stable and in healthy range.",
  "key_sensitivities": ["alcohol → HRV", "work_stress → HRV"],
  "key_strengths": ["sleep_consistency", "morning_routine"],
  "active_focus": "Phase 2 (Build) — introducing Zone 2 cardio 2-3x/week"
}
```

---

### C.4 Memory Write: Two Mechanisms

**Mechanism 1: Agent writes memory via a tool**

Add a `write_memory` tool to the agent's tool set:

```swift
[
    "name": "write_memory",
    "description": """
        Store a notable observation, user statement, pattern, or milestone 
        in long-term memory for recall in future sessions. 
        Use for: significant biometric events, patterns you've identified, 
        things the user told you, milestones reached, anomalous periods.
        Do NOT write trivial daily observations — only what would be 
        genuinely useful to recall in 2-4 weeks.
        """,
    "input_schema": [
        "type": "object",
        "required": ["type", "content", "tags", "importance"],
        "properties": [
            "type": [
                "type": "string",
                "enum": ["observation", "pattern", "milestone", "user_statement", "anomaly"]
            ],
            "content": ["type": "string", "description": "The memory content — 1-3 sentences."],
            "tags": ["type": "array", "items": ["type": "string"]],
            "importance": ["type": "string", "enum": ["low", "medium", "high"]]
        ]
    ]
]
```

The agent calls this tool at the end of sessions where something noteworthy was identified. The LLM decides what's worth remembering — you don't pre-define rules for it.

**Mechanism 2: Weekly review rewrites the identity summary**

Every Sunday, after the weekly coaching analysis, append a final instruction to the weekly review prompt:

```
After completing your weekly review, rewrite the user's identity summary 
in identity_summary.json. This is a living document — a 3-5 sentence 
compressed model of who this person is as a health subject, what their 
active focus is, what their sensitivities are, and what's working. 
Write it in third person. It will be injected into every future session.
```

The weekly review agent call gains access to a `write_identity_summary` tool.

---

### C.5 Memory Read: Injection Into Agent Frame

The lean agent frame from Phase B gains a memory section:

```swift
static func buildAgentFrame(
    summary: HealthSummary,
    baselineStatus: BaselineStatus,
    goalCount: Int,
    todayEvents: [String],
    memory: MemoryContext        // new
) -> String {
    """
    === PULSE AGENT — \(Date().formatted()) ===
    
    Baseline Status: \(baselineStatus.description)
    Active Goals: \(goalCount)
    Today's Events: \(todayEvents.joined(separator: ", "))
    
    === WHAT I KNOW ABOUT YOU ===
    \(memory.identitySummary)
    
    === RECENT NOTABLE EVENTS ===
    \(memory.recentEpisodic.map { "- [\($0.date)] \($0.content)" }.joined(separator: "\n"))
    
    === YOUR PATTERNS ===
    \(memory.patterns.map { "- \($0.description)" }.joined(separator: "\n"))
    
    [tools available as before]
    """
}
```

**`MemoryContext`** is assembled before each agent run:
- Identity summary: always injected (it's short)
- Episodic: last 5 high-importance entries + last 3 entries regardless of importance
- Patterns: all high-confidence patterns + medium-confidence patterns relevant to today's condition flags

This keeps the memory injection lean — typically 200-400 tokens — while ensuring the LLM has the most relevant context.

---

### C.6 Memory Maintenance

**Pruning (automatic, on app open weekly):**
- Episodic: keep last 60 entries. Prune oldest `low` importance entries first.
- Patterns: keep all. Maximum 30 patterns. If over limit, prune lowest confidence.
- Identity summary: no pruning — always a single document.

**No semantic deduplication in v1** — the LLM will naturally not write duplicate memories if the identity summary already reflects a pattern. Keep it simple.

---

### C.7 New File: `Models/MemoryStore.swift`

```swift
actor MemoryStore {
    private var episodic: [EpisodicMemory] = []
    private var patterns: [PatternMemory] = []
    private var identitySummary: IdentitySummary?
    
    // Called by ToolExecutor when agent calls write_memory
    func writeEpisodic(_ entry: EpisodicMemory) async throws
    func writePattern(_ pattern: PatternMemory) async throws
    func writeIdentitySummary(_ summary: IdentitySummary) async throws
    
    // Called by ContextBuilder to assemble memory injection
    func buildMemoryContext(relevantTags: Set<String>) -> MemoryContext
    
    // Maintenance
    func pruneIfNeeded() async throws
}
```

---

### C.8 What Pulse Becomes With Memory

Without memory (current):
> "Your HRV is 44ms, below your 7-day average of 61ms. You reported high stress. Here are some protocols."

With memory (Phase C):
> "Your HRV dropped to 44ms today — similar to what happened on February 12th when you had a stressful work week. Given that alcohol has consistently knocked your HRV down 15-25% in your history, tonight will be especially important to avoid it. You're in the Build phase of your goal and you don't want to lose the progress from last week's strong Zone 2 sessions. Physiological sigh and early sleep are your best levers right now."

That's a qualitatively different product.

---

## Implementation Notes for CLAUDE.md

Add this section to `CLAUDE.md` after the Phase B agentic section:

```markdown
## Long-Term Memory (Phase C)

Three memory tiers, all JSON in Documents directory:
- `episodic_memory.json` — notable events, max 60 entries
- `pattern_memory.json` — learned correlations, max 30 patterns
- `identity_summary.json` — compressed user model, single document

Memory READ: injected into agent frame via MemoryContext struct.
Memory WRITE: agent calls write_memory tool during sessions.
Identity summary: rewritten weekly by weekly review agent.

Memory injection is lean by design — identity summary + top 8 episodic 
entries + relevant patterns only. Target: <400 tokens of memory context.

MemoryStore is an actor. All reads/writes are async.
Weekly pruning: prune low-importance episodic entries beyond 60.
```

---

## Sequencing Summary

```
Current State
     │
     ▼
Phase A — LLM Interaction Log          (1-2 days)
     │  Adds: LLMInteractionStore, instrumented AnthropicClient, Log UI
     │  Risk: Low. Purely additive. No existing behavior changes.
     │
     ▼
Phase B — Agentic Tool Loop            (1-2 weeks)
     │  Adds: AgentRunner, ToolExecutor, 6 tools, lean ContextBuilder frame
     │  Migrates: Chat → agent, Weekly Review → agent, Morning Card → agent
     │  Risk: Medium. Migrate one feature at a time. Keep feature flags.
     │
     ▼
Phase C — Long-Term Memory             (1 week)
        Adds: MemoryStore (3 files), write_memory tool, memory injection
        Migrates: Agent frame gains memory context block
        Risk: Low-medium. Memory is additive context — worst case is verbose.
```

**Total estimated effort:** 3-4 weeks of focused development on top of the existing v1.0 foundation.

**The highest-leverage change is Phase B, Step 1 (Chat → agent).** It requires the least risk (Chat is the most forgiving feature) and delivers the most immediate improvement in response quality. Start there.
