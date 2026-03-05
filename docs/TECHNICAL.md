# Pulse — Technical Documentation

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [Data Layer](#data-layer)
3. [HealthKit Integration](#healthkit-integration)
4. [LLM Integration](#llm-integration)
5. [Agentic System](#agentic-system)
6. [Memory System](#memory-system)
7. [Protocol Corpus](#protocol-corpus)
8. [Goal & Progress System](#goal--progress-system)
9. [Safe Zone & Alert System](#safe-zone--alert-system)
10. [Context Assembly](#context-assembly)
11. [Notifications](#notifications)
12. [Error Handling](#error-handling)
13. [Data Flows](#data-flows)
14. [File Reference](#file-reference)

---

## Architecture Overview

Pulse is a single-module SwiftUI application targeting iOS 17+. It has no third-party dependencies.

### Layers

```
Views (SwiftUI)
    ↕ @Observable ViewModels (@MainActor)
Services (actors: AnthropicClient, ToolExecutor, AgentRunner)
    ↕
Models (actors: TrendStore, GoalStore, ProgressStore, MemoryStore)
    ↕
Persistence (JSON files in Documents directory)
```

### Concurrency Model

- All **stores** are `actor` — serialised access, no data races
- All **ViewModels** are `@Observable @MainActor` — UI updates always on main thread
- All **services** that manage shared state (AnthropicClient, ToolExecutor) are `actor`
- **HealthKitManager** is a plain class; its methods are `async` wrappers around HealthKit completion-handler queries
- Stores are initialised once in the app entry point and passed down via environment or direct injection

### Storage

All persistence is JSON files in the app's Documents directory. Writes use `.atomic` option. There is no CoreData, no SQLite, no iCloud.

| File | Actor | Contents |
|---|---|---|
| `trend_store.json` | TrendStore | 30-day rolling health history, computed baselines |
| `goal_store.json` | GoalStore | Outcome goal definitions, activity alert configs |
| `progress_store.json` | ProgressStore | Weekly snapshots, phase history per goal |
| `episodic_memory.json` | MemoryStore | Notable events written by the weekly review agent |
| `pattern_memory.json` | MemoryStore | Learned correlations and behavioral patterns |
| `identity_summary.json` | MemoryStore | Compressed user model updated weekly |
| `daily_tasks.json` | DailyTaskStore (static) | Today's action items (date-keyed, cleared daily) |

Two additional caches live in UserDefaults:
- `morning_card_*` — today's parsed morning card
- `weekly_review_*` — this week's generated review (avoids re-running)

---

## Data Layer

### HealthSummary

The primary data object. Represents a single day's health metrics. All fields are optional — absence is normal and handled explicitly.

```swift
struct HealthSummary: Codable {
    let date: Date
    var hrv: Double?             // ms SDNN — previous night's average
    var restingHR: Double?       // bpm — today's Apple-computed value
    var sleepHours: Double?      // hours — sum of asleepCore + asleepDeep + asleepREM
    var sleepEfficiency: Double? // 0.0–1.0 = asleep / timeInBed
    var respiratoryRate: Double? // breaths/min — sleep average
    var activeCalories: Double?  // kcal — yesterday's total
    var steps: Int?              // yesterday's total
    var wakeTime: Date?          // end of last sleep sample
    var todayCalories: Double?   // kcal — midnight to now
    var todaySteps: Int?         // midnight to now
    var vo2Max: Double?          // mL/(kg·min) — most recent 90-day Watch estimate
    var cardioRecovery: Double?  // bpm drop at 1 min post-exercise — most recent 30 days
    var walkingHeartRate: Double?// bpm — yesterday average (walkingHeartRateAverage)
    var walkingSpeed: Double?    // m/s — 7-day rolling average
    var stairAscentSpeed: Double?// m/s — 7-day rolling average
    var stairDescentSpeed: Double?// m/s — 7-day rolling average
}
```

**Null rule:** when a metric is nil, context builders emit `"not available (reason)"`. The LLM is never given zero or empty string in place of missing data.

### TrendStore

Maintains a rolling 30-day history of `DayEntry` records and derived baselines.

```swift
actor TrendStore {
    func update(with summary: HealthSummary) async throws  // upsert today + recompute baselines
    func recordAlcohol(_ reported: Bool, for date: Date) async throws
    func recordEvents(_ events: [String], for date: Date) async throws
    var baselines: Baselines { get }
    var baselineStatus: BaselineStatus { get }  // cold | building | established
    var history: [DayEntry] { get }
}
```

`update(with:)` preserves existing `alcoholReported` and `events` when upserting the current day — health data overwrites health fields, but user-logged fields are sticky.

**Baseline computation** is called on every `update`. Averages are computed over `last7` and `last30` slices of the sorted history array.

### BaselineStatus

```swift
enum BaselineStatus: String, Codable {
    case cold         // 0–6 days — use population references
    case building     // 7–29 days — personal baseline forming
    case established  // 30+ days — full personalisation active
}
```

This is injected into every LLM context and controls how the model calibrates its confidence.

### GoalStore

```swift
actor GoalStore {
    var goals: [GoalDefinition] { get }
    var activityAlerts: [ActivityAlert] { get }
    func save(goal: GoalDefinition) async throws
    func delete(goalId: String) async throws
}
```

`GoalDefinition` key fields:

```swift
struct GoalDefinition: Codable, Identifiable {
    let id: String
    let metric: GoalMetric        // hrv | resting_hr | respiratory_rate
    let targetValue: Double
    let baselineAtSet: Double     // snapshot of baseline when goal was created
    let mode: GoalMode            // target | maintain
    var currentPhase: Int?        // 1–3
    var weeklySnapshots: [WeeklySnapshot]
    var safeZone: SafeZoneConfig
    var timeframeWeeks: Int?
}
```

### ProgressStore

Manages phase history and weekly snapshots separately from goal definitions, keyed by `goalId`.

```swift
actor ProgressStore {
    func progress(for goalId: String) -> GoalProgress?
    func initializeProgress(for goal: GoalDefinition) throws
    func recordWeeklySnapshot(goalId:sevenDayAvg:baseline:goal:) throws -> Bool
}
```

`recordWeeklySnapshot` returns `true` when the phase advances. Phase advancement fires a local notification.

**Advancement logic** (`checkAdvancement`): the 7-day average must be at or above the sub-target upper bound for 2 consecutive weekly snapshots.

---

## HealthKit Integration

### Authorisation

Requested once at first launch, all types at once:

```swift
let readTypes: Set<HKObjectType> = [
    .categoryType(forIdentifier: .sleepAnalysis)!,
    .quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    .quantityType(forIdentifier: .restingHeartRate)!,
    .quantityType(forIdentifier: .respiratoryRate)!,
    .quantityType(forIdentifier: .activeEnergyBurned)!,
    .quantityType(forIdentifier: .stepCount)!,
    .quantityType(forIdentifier: .vo2Max)!,
    .quantityType(forIdentifier: .heartRateRecoveryOneMinute)!,
    .quantityType(forIdentifier: .walkingHeartRateAverage)!,
    .quantityType(forIdentifier: .walkingSpeed)!,
    .quantityType(forIdentifier: .stairAscentSpeed)!,
    .quantityType(forIdentifier: .stairDescentSpeed)!
]
```

### Query Patterns

All queries are `async throws` wrappers using `withCheckedThrowingContinuation`:

**Sample query** — used for HRV, respiratory rate, walking speed, walking HR:
```swift
HKSampleQuery(sampleType:predicate:limit:sortDescriptors:) { _, samples, error in
    continuation.resume(...)
}
```

**Statistics query** — used for calories and steps (cumulative sum):
```swift
HKStatisticsQuery(quantityType:quantitySamplePredicate:options:.cumulativeSum) { _, stats, error in
    continuation.resume(returning: stats?.sumQuantity()?.doubleValue(for: unit))
}
```

**Sleep** uses `HKCategoryType(.sleepAnalysis)`. Stages are combined:
- Sleep duration = sum of `.asleepCore` + `.asleepDeep` + `.asleepREM` samples
- Time in bed = `latestEndDate − earliestStartDate` across all samples
- Efficiency = duration / timeInBed, capped at 1.0

**HRV** window: 9pm prior day → 9am today (approximate sleep window).

**Resting HR**: single most recent sample from `startOfDay(today)` to now.

**VO2 Max unit** is constructed programmatically (string initialisation is unreliable):
```swift
HKUnit.literUnit(with: .milli)
    .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: HKUnit.minute()))
```

**Walking Heart Rate** uses `.walkingHeartRateAverage` (not `.walkingHeartRate` — that identifier does not exist in HealthKit).

---

## LLM Integration

### AnthropicClient

An `actor` making direct REST calls to `https://api.anthropic.com/v1/messages`.

Required headers:
```
x-api-key: {apiKey}
anthropic-version: 2023-06-01
content-type: application/json
```

Two call surfaces:

**`rawComplete`** — low-level, returns `(text, inputTokens, outputTokens)`. Used by `instrumentedComplete`.

**`completeWithTools`** — for agentic sessions. Returns `AnthropicResponse`:
```swift
struct AnthropicResponse {
    let text: String                    // empty when stop_reason == "tool_use"
    let toolCalls: [AnthropicToolCall]  // empty when stop_reason == "end_turn"
    let rawContent: [[String: Any]]     // full content array — appended as-is to message history
    let inputTokens: Int?
    let outputTokens: Int?
    let stopReason: String
}
```

All completions pass through `instrumentedComplete`, which measures wall-clock duration and writes an `LLMInteraction` record to `LLMInteractionStore`.

### Model Selection

| Feature | Model |
|---|---|
| Morning card (agentic) | claude-haiku-4-5-20251001 |
| Check-in (single-shot) | claude-haiku-4-5-20251001 |
| Chat — simple | claude-haiku-4-5-20251001 |
| Chat — complex (contains "week", "month", "trend", "goal progress") | claude-sonnet-4-6 |
| Weekly review (agentic) | claude-sonnet-4-6 |

Model IDs are configurable via `Config.plist` keys `DefaultModel` and `AnalysisModel`.

### Prompts

All prompts are constants in `Services/Prompts.swift`. Never constructed dynamically. Key constants:

| Constant | Used by |
|---|---|
| `Prompts.system` | Legacy single-shot calls |
| `Prompts.agentSystem` | All agentic runs via AgentRunner |
| `Prompts.morningCardAgentInstruction` | Morning card agent turn 1 |
| `Prompts.weeklyReviewAgentInstruction` | Weekly review agent turn 1 |
| `Prompts.chatAgentInstruction` | Chat agent turn 1 |
| `Prompts.checkInInstruction` | Check-in single-shot |

The agent system prompt instructs the LLM to: always call `get_baseline` first, never claim trends without calling `get_trend_stats`, use exact protocol IDs from corpus, and not invent data.

---

## Agentic System

### AgentRunner

Implements a tool-use loop with a maximum of 8 iterations.

```
User message (agent frame + instruction)
    → LLM responds (text or tool_use blocks)
    → If tool_use: execute tools, append tool results as user message
    → Loop until stop_reason == "end_turn" or max iterations
    → Return final text
```

Message history format follows the Anthropic API multi-turn structure. The `rawContent` array from each assistant response is appended verbatim, followed by a user message containing all tool results for that round.

Tool result message format:
```json
{
  "role": "user",
  "content": [
    {
      "type": "tool_result",
      "tool_use_id": "<id from tool_use block>",
      "content": "<JSON string returned by ToolExecutor>"
    }
  ]
}
```

If 8 iterations are reached without `end_turn`, `AgentRunner` throws `AppError.agentMaxIterationsReached`. Callers catch this and fall back to single-shot completion.

All iterations are logged to `LLMInteractionStore` with `iterationCount` set to the total rounds taken.

### AgentTools

Nine tool definitions in `AgentTools.definitions`:

| Tool | Key inputs | Returns |
|---|---|---|
| `get_health_data` | `date` or `days_back` | Array of day entries with all metrics |
| `get_trend_stats` | `metric`, `days` | mean, min, max, std_dev, trend_direction, slope |
| `get_baseline` | `metric` (optional) | Personal averages + baseline_status |
| `get_goal_progress` | `metric` (optional) | Goal definitions, phase info, pace, snapshots |
| `get_protocols` | `conditions[]`, `max_effort` | Matching protocols from corpus |
| `get_correlation` | `metric_a`, `metric_b`, `days` | Pearson r, direction, interpretation |
| `write_memory` | `type`, `content`, `tags`, `importance` | Confirmation |
| `write_identity_summary` | `summary`, `key_sensitivities`, `key_strengths`, `active_focus` | Confirmation |
| `add_task` | `title`, `protocol_id` (optional) | Confirmation + task_id |

**Metric enum values** (used in get_trend_stats, get_correlation, get_baseline):
`hrv`, `resting_hr`, `respiratory_rate`, `sleep_hours`, `sleep_efficiency`, `active_calories`, `steps`, `vo2max`, `walking_speed`, `walking_hr`, `cardio_recovery`, `stair_ascent_speed`, `stair_descent_speed`

**Condition flags** (used in get_protocols):
`low_hrv`, `very_low_hrv`, `elevated_rhr`, `poor_sleep`, `elevated_respiratory_rate`, `high_stress`, `possible_illness`, `well_recovered`, `peak_readiness`

### ToolExecutor

An `actor` that executes tool calls and returns JSON strings.

Key implementation details:

- `getTrendStats` computes a linear regression slope (least-squares) over the window and classifies trend as improving/declining/stable based on a 0.5%/day threshold
- `getCorrelation` computes Pearson r from paired days where both metrics have values; requires ≥5 paired days
- Metrics where *lower is better* (`resting_hr`, `respiratory_rate`, `walking_hr`) have their trend direction inverted: a falling slope is "improving"
- `addTask` directly writes to `DailyTaskStore` (static JSON), usable from any actor context

---

## Memory System

Three independent memory layers, all managed by `MemoryStore`.

### Episodic Memory

Notable events written by the weekly review agent or chat agent.

```swift
struct EpisodicMemory: Identifiable, Codable {
    let id: String            // UUID
    let date: String          // YYYY-MM-DD
    let type: String          // observation | pattern | milestone | user_statement | anomaly
    let content: String       // 1–3 sentences, specific numbers
    let tags: [String]        // e.g. ["hrv", "stress", "travel"]
    let importance: String    // low | medium | high
    let source: String        // morning_card | chat | weekly_review
}
```

Capacity: 60 entries. On overflow, lowest-importance entries are pruned first, then oldest.

### Pattern Memory

Learned correlations and behavioural drivers, updated by the weekly review.

```swift
struct PatternMemory: Identifiable, Codable {
    let id: String
    let metric: String
    let patternType: String   // correlation | trigger | recovery | baseline_shift
    let description: String
    var confidence: String    // low | medium | high
    var evidenceCount: Int
    var lastObserved: String
    let tags: [String]
}
```

Capacity: 30 entries. Pruned by lowest confidence first.

### Identity Summary

A single compressed user model, overwritten by each weekly review.

```swift
struct IdentitySummary: Codable {
    let summary: String           // 3–5 sentences, third person
    let keySensitivities: [String]// e.g. ["alcohol → HRV", "work_stress → HRV"]
    let keyStrengths: [String]    // e.g. ["sleep_consistency", "morning_routine"]
    let activeFocus: String       // e.g. "Phase 2 (Build) — Zone 2 cardio 2-3x/week"
    let lastUpdated: String       // YYYY-MM-DD
    let generatedBy: String       // "weekly_review"
}
```

### Memory Injection

Before each agent run, `MemoryStore.buildMemoryContext()` selects:
- Identity summary (always, if present)
- Up to 5 high-importance episodic entries + last 3 episodic entries (deduplicated)
- All high-confidence patterns

This is injected into `ContextBuilder.buildAgentFrame()` as structured text sections.

---

## Protocol Corpus

`Resources/protocols.json` is a bundled, read-only array of protocol objects loaded once at startup by `ProtocolMatcher`.

### Schema

```json
{
  "id": "physiological_sigh",
  "title": "Physiological Sigh",
  "category": "stress_regulation",
  "tags": ["breathing", "stress", "anxiety", "real_time"],
  "trigger_conditions": ["high_stress", "low_hrv", "elevated_respiratory_rate"],
  "duration_minutes": 10,
  "effort": 0,
  "timing": "anytime",
  "protocol": "Double-inhale through the nose (sniff, then sniff again to maximally inflate lungs), then a long, slow exhale through the mouth...",
  "why_it_works": "The double inhale re-inflates collapsed alveoli. The extended exhale activates the parasympathetic branch via the vagus nerve...",
  "source": "Huberman Lab — Breathing Tools for Stress & Anxiety (2022)",
  "phase_relevance": ["phase_1", "phase_2"]
}
```

### Effort Scale

| Value | Label |
|---|---|
| 0 | None — passive or minimal |
| 1 | Low — light effort, no equipment |
| 2 | Medium — moderate engagement |
| 3 | High — significant physical or cognitive demand |
| 4 | Very high — intense exercise or extended session |

### Condition Flag Evaluation

`ProtocolMatcher.evaluateFlags(summary:baselines:events:)` returns a `Set<String>` of flags:

| Flag | Condition |
|---|---|
| `very_low_hrv` | HRV < 70% of 7-day baseline |
| `low_hrv` | HRV < 85% of 7-day baseline |
| `peak_readiness` | HRV ≥ 110% of 7-day baseline, sleep ≥ 7h |
| `elevated_rhr` | Resting HR > 30-day average + 5 bpm |
| `poor_sleep` | Sleep < 6h OR efficiency < 0.75 |
| `elevated_respiratory_rate` | Respiratory rate > 30-day average + 1.5 br/min |
| `high_stress` | events contains high_stress or `elevated_rhr` + `low_hrv` together |
| `possible_illness` | `elevated_respiratory_rate` + `elevated_rhr` |
| `well_recovered` | None of the negative flags present |

Protocol selection: `matchByFlags(flags:maxEffort:)` filters the corpus to protocols whose `trigger_conditions` intersect the active flags, then sorts by effort (ascending on low-readiness days, descending on high-readiness).

---

## Goal & Progress System

### Goal Modes

**Target** — user has a numeric target. Has a three-phase plan. Progress is tracked weekly.

**Maintain** — baseline is the target. Only safe zone violations shown. No phases.

### Phase Model (Target Goals Only)

`HRVPhasePlan.phases(baseline:target:)` generates three phases:

| Phase | Focus | Sub-target range |
|---|---|---|
| 1 — Stabilize | Consistent sleep, eliminate alcohol, morning sunlight | baseline+1 to baseline+2 |
| 2 — Build | Zone 2 cardio 2–3×/week, NSDR, cold exposure | baseline + 30–50% of gap |
| 3 — Optimize | Training load management, meal timing, alcohol minimised | baseline + 80% of gap to target |

Phase advancement: `checkAdvancement()` requires the 7-day average to be ≥ the sub-target upper bound for 2 consecutive weekly snapshots.

### Weekly Snapshot Recording

Called after the weekly review agent completes. `PaceCalculator.computePace()` evaluates the latest snapshot against the phase sub-target and returns: `ahead`, `on_track`, `behind`, or `stalled`.

### Safe Zone Configuration

Per-goal configurable in `GoalSetupView`. Stored in `SafeZoneConfig`:

```swift
struct SafeZoneConfig: Codable {
    var warningThreshold: Double  // trigger a warning banner
    var alertThreshold: Double    // trigger an alert banner
    var isRelative: Bool          // true = % of baseline, false = absolute value
}
```

HRV uses relative thresholds by default (e.g. warning at 85% of baseline). RHR and respiratory rate use absolute values (e.g. warning when RHR > baseline + 5).

### Conflict Detection

`GoalConflictDetector.check(newGoal:existingGoals:)` flags conflicts shown as a warning sheet (does not block saving):
- Duplicate metric goals
- HRV target goal + HRV maintain goal simultaneously

---

## Safe Zone & Alert System

`TodayViewModel.evaluateSafeZones()` runs on app open and after health data is fetched.

Default thresholds (overridden by per-goal `SafeZoneConfig` where applicable):

| Metric | Warning | Alert |
|---|---|---|
| HRV | < 85% of 7-day avg | < 75% of 7-day avg |
| Resting HR | ≥ 60 bpm or +5 above 30d avg | ≥ 63 bpm or +8 above 30d avg |
| Respiratory Rate | ≥ 17 br/min | ≥ 19 br/min |
| Walking Speed | < 1.0 m/s | < 0.8 m/s |
| VO2 Max | < 95% of 30-day avg | < 92% of 30-day avg |
| Cardio Recovery | < 12 bpm drop | < 8 bpm drop |

Alerts are displayed as `AlertBannerView` cards at the top of the Today tab with the current value, baseline, and percentage deviation.

---

## Context Assembly

`ContextBuilder` assembles the text injected into LLM sessions.

### Agent Frame (Agentic Mode)

`buildAgentFrame(baselineStatus:goalCount:todayEvents:memory:dailyTasks:)` produces:

```
=== PULSE AGENT — Wednesday, 5 March 2026 at 07:42 AM ===

Baseline Status: established (34 days of history — full personal baseline active)
Active Goals: 1
Today's Reported Events: high_stress

=== TODAY'S ACTIONS ===
○ [morning] Do 10 min of physiological sighs before noon
✓ [morning] Morning sunlight — 10 min outside within 30 min of waking

=== WHAT I KNOW ABOUT YOU ===
[identity summary if present]

=== RECENT NOTABLE EVENTS ===
[selected episodic memories if present]

=== YOUR PATTERNS ===
[high-confidence patterns if present]
```

This is the first user message in an agentic session, followed by the feature-specific instruction (e.g. `morningCardAgentInstruction`).

### Morning Context (Legacy / Check-in)

`buildMorningContext()` produces a plain-text health summary block including:
- All metrics with delta vs. baseline
- Today's logged events
- Active goals summary
- Available matched protocols
- Mode identifier

---

## Notifications

`NotificationScheduler` manages three notification types using `UNUserNotificationCenter`.

| Notification | Trigger | Identifier |
|---|---|---|
| Morning Readiness | Daily calendar trigger at user's wake time | `pulse.morning` |
| Weekly Coaching | Sunday 8:00 AM calendar trigger | `pulse.weekly` |
| Activity Nudge | Daily 5:00 PM calendar trigger | `pulse.activity` |

The Activity Nudge is pre-evaluated in the foreground: if today's steps and calories are already above the configured `alertBelow` thresholds for all activity alerts, the notification request is removed rather than scheduled.

No background HealthKit delivery is used.

---

## Error Handling

### AppError

```swift
enum AppError: Error {
    case healthKitUnavailable
    case healthKitAuthorizationDenied
    case healthKitQueryFailed(String)
    case apiFailure(String)
    case jsonParseFailed(String)
    case storeLoadFailed(String)
    case storeSaveFailed(String)
    case configMissing(String)
    case agentMaxIterationsReached
}
```

All cases have a `userMessage: String` computed property used for UI display.

### Fallback Chain

| Failure | Fallback |
|---|---|
| `agentMaxIterationsReached` | Single-shot call to `completeMorningCard()` / `completeChat()` |
| LLM JSON parse failure | Display raw response text in morning card area |
| API call failure | Show error alert with Retry button |
| Store load failure | Initialise with empty/default values (never crash) |
| HealthKit nil metric | Pass nil to ContextBuilder; emit `"not available"` in context |
| HealthKit permission denied per metric | Graceful nil handling; show "data unavailable" in UI |
| Agent loop produces empty text | Fall back to last non-empty text block in history |

---

## Data Flows

### Morning Card (Agentic)

```
TodayView.onAppear
  → TodayViewModel.bootstrap()
      → TrendStore.load()
      → GoalStore.load()
      → ProgressStore.load()
      → MemoryStore.load()
  → TodayViewModel.generateMorningCard()
      → HealthKitManager.fetchTodaySummary()      — parallel HK queries
      → TrendStore.update(with: summary)           — upsert + recompute baselines
      → ContextBuilder.buildAgentFrame(...)        — assemble header + memory
      → AgentRunner.run(feature: .morningCard, instruction: Prompts.morningCardAgentInstruction)
          — tool loop (haiku, max 8 iterations):
            get_baseline → get_health_data → get_goal_progress → get_protocols
          → returns AgentResult
      → JSONDecoder.decode(MorningCardResponse)    — or fallback to raw text
      → MorningCardStore.save(card)               — persists for the day
      → populateTasksFromMorningCard(card)         — writes DailyTaskStore
      → evaluateSafeZones()                        — checks baselines → sets alertBanners
```

### Chat (Agentic)

```
ChatView → user sends message
  → ChatViewModel.send(text)
      → HealthKitManager.fetchTodaySummary()      — live metrics at time of send
      → TrendStore.update(with: summary)
      → DailyTaskStore.loadIfToday()              — current task list
      → ContextBuilder.buildAgentFrame(...)
      → append pendingChatContext (check-in context if routed from Today)
      → append user message
      → AgentRunner.run(feature: .chat, model: haiku or sonnet)
          — tool loop (max 8 iterations):
            get_baseline, get_trend_stats, get_health_data, get_correlation,
            get_protocols, write_memory, add_task (if suggestion made)
          → returns AgentResult
      → append assistant message to history
      → show tool summary beneath response
```

### Weekly Review (Agentic)

```
TodayView → "Generate Weekly Review"
  → WeeklyReviewViewModel.generate()
      → WeeklyReviewStore.loadIfThisWeek()        — return cached if available
      → ContextBuilder.buildAgentFrame(...)
      → AgentRunner.run(feature: .weeklyReview, model: sonnet)
          — tool loop (sonnet, max 8 iterations):
            get_baseline, get_health_data(7d), get_health_data(14d),
            get_trend_stats (per metric), get_goal_progress, get_correlation,
            write_memory (notable events), write_identity_summary
          → returns AgentResult
      → JSONDecoder.decode(WeeklyReviewResponse)
      → WeeklyReviewStore.save(review)
      → ProgressStore.recordWeeklySnapshot(...)    — updates phase + pace
```

---

## File Reference

### App

| File | Purpose |
|---|---|
| `App/PulseApp.swift` | App entry point, store initialisation, notification setup |
| `App/ContentView.swift` | TabView root, PendingChatContext binding, LLM log sheet |

### Models

| File | Purpose |
|---|---|
| `Models/HealthSummary.swift` | Daily health snapshot struct |
| `Models/TrendStore.swift` | Rolling history actor |
| `Models/TrendStoreData.swift` | Codable wrapper: DayEntry, Baselines, BaselineStatus |
| `Models/GoalStore.swift` | Outcome goals and activity alerts actor |
| `Models/GoalStoreData.swift` | GoalDefinition, ActivityAlert, SafeZoneConfig, GoalMetric |
| `Models/ProgressStore.swift` | Weekly snapshot and phase history actor; HRVPhasePlan |
| `Models/ProgressStoreData.swift` | GoalProgress, PhaseRecord, PhaseSnapshot |
| `Models/MemoryStore.swift` | Three-layer memory actor |
| `Models/MemoryModels.swift` | EpisodicMemory, PatternMemory, IdentitySummary |
| `Models/DailyTask.swift` | DailyTask struct |
| `Models/DailyTaskStore.swift` | Date-keyed task persistence (static methods) |
| `Models/AppError.swift` | Typed error enum with userMessage |
| `Models/MorningCardResponse.swift` | Parsed morning card JSON structure |
| `Models/CheckInResponse.swift` | Parsed check-in JSON structure |
| `Models/WeeklyReviewResponse.swift` | Parsed weekly review structure |
| `Models/MorningCardStore.swift` | UserDefaults cache for today's card |
| `Models/WeeklyReviewStore.swift` | UserDefaults cache for this week's review |
| `Models/LLMInteractionLog.swift` | LLMInteraction and LoggedMessage structs |
| `Models/LLMInteractionStore.swift` | Singleton actor for LLM audit log |
| `Models/APIKeyStore.swift` | Config.plist + UserDefaults key management |
| `Models/Protocol.swift` | WellnessProtocol struct |

### Services

| File | Purpose |
|---|---|
| `Services/HealthKitManager.swift` | All HealthKit queries |
| `Services/AnthropicClient.swift` | Anthropic REST actor; feature-specific completion methods |
| `Services/AgentRunner.swift` | Tool-use loop orchestration |
| `Services/AgentTools.swift` | Tool schema definitions + Dictionary.jsonString helper |
| `Services/ToolExecutor.swift` | Tool implementation actor |
| `Services/ContextBuilder.swift` | Agent frame and context text assembly |
| `Services/ProtocolMatcher.swift` | Condition flag evaluation and protocol selection |
| `Services/PaceCalculator.swift` | Goal pace assessment |
| `Services/NotificationScheduler.swift` | Local notification scheduling |
| `Services/Prompts.swift` | All LLM prompt string constants |

### Views

| File | Purpose |
|---|---|
| `Views/Today/TodayView.swift` | Today tab root |
| `Views/Today/TodayViewModel.swift` | Today tab state and logic |
| `Views/Today/MorningCardView.swift` | Parsed morning card renderer; FlowLayout |
| `Views/Today/AlertBannerView.swift` | Safe zone warning/alert card |
| `Views/Today/WeeklyReviewView.swift` | Weekly review renderer |
| `Views/Today/WeeklyReviewViewModel.swift` | Weekly review generation |
| `Views/Chat/ChatView.swift` | Chat conversation UI |
| `Views/Chat/ChatViewModel.swift` | Chat state and agentic send logic |
| `Views/Chat/MessageBubbleView.swift` | Chat bubble renderer |
| `Views/Progress/GoalProgressTab.swift` | Progress tab root |
| `Views/Progress/GoalProgressCardView.swift` | Per-goal progress card |
| `Views/Progress/SparklineView.swift` | Custom SwiftUI sparkline shape |
| `Views/Goals/GoalsView.swift` | Goal list and activity alerts |
| `Views/Goals/GoalSetupView.swift` | Goal creation / edit modal |
| `Views/Goals/GoalsViewModel.swift` | Goal CRUD and conflict detection |
| `Views/Goals/ActivityAlertView.swift` | Activity alert setup modal |
| `Views/Settings/SettingsView.swift` | Settings (API key, debug links) |
| `Views/Settings/LLMLogView.swift` | LLM interaction audit log |
| `Views/Settings/MemoryDebugView.swift` | Memory layer inspector |

### Resources

| File | Purpose |
|---|---|
| `Resources/protocols.json` | Bundled Huberman Lab protocol corpus |
| `Config/Config.plist` | API key + model name config (gitignored) |
