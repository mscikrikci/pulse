# CLAUDE.md — Pulse iOS App

## Role & Expertise

You are an experienced iOS developer building a personal wellness coaching app called **Pulse**. You write clean, idiomatic Swift and SwiftUI. You are familiar with HealthKit, local data persistence, async/await patterns, and direct REST API integration. You prefer simple, debuggable solutions over over-engineered abstractions — this is a personal prototype, not an enterprise app.

When making architectural decisions, default to the simplest approach that works correctly. Avoid introducing dependencies or patterns that aren't justified by the current scope.

---

## Project Overview

Pulse is a personal iOS wellness coaching app that:
- Reads Apple Health data via HealthKit (read-only)
- Maintains local trend baselines and goal progress in JSON files on device
- Generates a daily morning readiness card and weekly coaching summary via LLM
- Answers ad-hoc wellness questions via a chat interface
- Suggests evidence-based protocols from a bundled Huberman Lab corpus
- Tracks progress toward outcome goals (HRV, Resting HR, Sleep Respiratory Rate)

**This is a personal prototype. There is no backend, no user accounts, no cloud sync.**

Full design specification: `docs/design.md`

---

## Technology Stack

| Layer | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI | SwiftUI |
| Minimum iOS | iOS 17 |
| Health Data | HealthKit (read-only) |
| Local Storage | JSON files in app Documents directory (no CoreData) |
| LLM | Anthropic API — direct REST calls (no SDK) |
| Default Model | claude-haiku-4-5-20251001 (daily cards, alerts) |
| Analysis Model | claude-sonnet-4-6 (weekly review, complex chat) |
| API Key | Config.plist (gitignored — never commit) |
| Build Tool | Xcode (available on local Mac) |
| Package Manager | Swift Package Manager only (no CocoaPods, no Carthage) |

**No third-party dependencies unless absolutely necessary.** If you need to add a package, ask first and justify it.

---

## Project Structure

```
Pulse/
├── CLAUDE.md                          ← this file
├── docs/
│   └── design.md                      ← full design document
├── Pulse.xcodeproj/
├── Pulse/
│   ├── App/
│   │   ├── PulseApp.swift
│   │   └── ContentView.swift          ← tab bar root
│   ├── Config/
│   │   └── Config.plist               ← API key (gitignored)
│   ├── Models/
│   │   ├── HealthSummary.swift        ← struct for a single day's metrics
│   │   ├── TrendStore.swift           ← codable model + read/write logic
│   │   ├── GoalStore.swift            ← codable model + read/write logic
│   │   ├── ProgressStore.swift        ← codable model + read/write logic
│   │   └── Protocol.swift             ← wellness protocol struct
│   ├── Services/
│   │   ├── HealthKitManager.swift     ← all HealthKit queries
│   │   ├── ContextBuilder.swift       ← assembles LLM context from stores + summary
│   │   ├── ProtocolMatcher.swift      ← condition flags → protocol retrieval
│   │   ├── AnthropicClient.swift      ← REST calls to Anthropic API
│   │   ├── NotificationScheduler.swift
│   │   └── PaceCalculator.swift       ← weekly pace assessment logic
│   ├── Views/
│   │   ├── Today/
│   │   │   ├── TodayView.swift
│   │   │   ├── MorningCardView.swift
│   │   │   └── AlertBannerView.swift
│   │   ├── Progress/
│   │   │   ├── ProgressView.swift
│   │   │   ├── GoalProgressCardView.swift
│   │   │   └── SparklineView.swift
│   │   ├── Goals/
│   │   │   ├── GoalsView.swift
│   │   │   ├── GoalSetupView.swift
│   │   │   └── ActivityAlertView.swift
│   │   └── Chat/
│   │       ├── ChatView.swift
│   │       └── MessageBubbleView.swift
│   ├── Resources/
│   │   └── protocols.json             ← bundled Huberman protocol corpus
│   └── Extensions/
│       ├── Date+Extensions.swift
│       └── Double+Extensions.swift
└── .gitignore                         ← must include Config.plist
```

---

## Data Architecture

### Storage Files (all in app Documents directory)

| File | Purpose | Updated |
|---|---|---|
| `trend_store.json` | Rolling baselines, 30-day history | On app open |
| `goal_store.json` | Goal definitions, safe zone config, activity alerts | On goal save |
| `progress_store.json` | Weekly snapshots, phase history, pace assessment | Weekly (Sunday) |

### Key Data Structures

**HealthSummary** — a single day's metrics, used as the primary data object passed to ContextBuilder:
```swift
struct HealthSummary: Codable {
    let date: Date
    var hrv: Double?                    // ms, nil if unavailable
    var restingHR: Double?              // bpm
    var sleepHours: Double?             // total hours
    var sleepEfficiency: Double?        // 0.0-1.0
    var respiratoryRate: Double?        // breaths/min during sleep
    var activeCalories: Double?         // kcal
    var steps: Int?
}
```

**Always use optionals for all health metrics.** HealthKit data is frequently absent (watch not worn, data not synced). Never force-unwrap. Always pass `nil` to context builder and let it handle gracefully.

### Null Handling Rule

When a metric is nil, the context builder must emit:
```
HRV: not available (Watch not worn or data not recorded)
```
Never omit the field silently. Never pass an empty string. The LLM must know data is absent, not zero.

### Baseline Status

TrendStore must expose a `baselineStatus` computed property:
- `cold` — fewer than 7 days of history
- `building` — 7-29 days
- `established` — 30+ days

This is passed in every LLM context block and affects how the LLM calibrates confidence.

---

## HealthKit Integration

### Permissions

Request at onboarding (first app launch). Request all metrics at once. Do not drip-request.

```swift
let readTypes: Set<HKObjectType> = [
    HKObjectType.categoryType(forIdentifier: .sleepAnalysis)!,
    HKObjectType.quantityType(forIdentifier: .heartRateVariabilitySDNN)!,
    HKObjectType.quantityType(forIdentifier: .restingHeartRate)!,
    HKObjectType.quantityType(forIdentifier: .respiratoryRate)!,
    HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
    HKObjectType.quantityType(forIdentifier: .stepCount)!
]
```

### Query Patterns

Use `HKSampleQuery` with date predicates. All queries are async/await wrapped. Do not use completion handler callbacks directly in views.

Sleep analysis requires combining multiple `HKCategoryValueSleepAnalysis` stages:
- Sum `.asleepCore`, `.asleepDeep`, `.asleepREM` for total sleep duration
- Efficiency = total asleep / (latestEndDate - earliestStartDate)

HRV: query `heartRateVariabilitySDNN` samples from previous night's sleep window (approximate: 9pm prior day to 9am today), take average.

Resting HR: single daily `restingHeartRate` sample — Apple computes this automatically.

### No Background HealthKit

Do not implement `HKObserverQuery` or background delivery in v1. All queries are foreground, on-demand only.

---

## LLM Integration

### AnthropicClient

Direct REST — no SDK. Implement as an actor for thread safety:

```swift
actor AnthropicClient {
    private let apiKey: String
    private let session = URLSession.shared
    
    func complete(
        system: String,
        messages: [[String: Any]],
        model: String,
        maxTokens: Int = 1024
    ) async throws -> String
}
```

Endpoint: `https://api.anthropic.com/v1/messages`

Required headers:
```
x-api-key: {apiKey}
anthropic-version: 2023-06-01
content-type: application/json
```

Parse `response.content[0].text` for the completion text.

### Morning Card Response

The LLM is asked to return JSON. Parse it — but always wrap in a do/catch and fall back to displaying the raw text if JSON parsing fails. Do not crash on malformed LLM output.

```swift
struct MorningCardResponse: Codable {
    let readinessLevel: String          // "high" | "medium" | "low" | "alert"
    let headline: String
    let summary: String
    let workSuggestion: String
    let protocols: [ProtocolSuggestion]
    let avoidToday: [String]
    let oneFocus: String
    let goalNote: String
}
```

### Model Selection

```swift
enum LLMTask {
    case morningCard        // haiku
    case activityAlert      // haiku
    case weeklyReview       // sonnet
    case chat(isComplex: Bool)  // haiku for simple, sonnet for multi-week trend questions
}
```

A chat question is "complex" if it references time ranges longer than 7 days or asks about goal progress trends.

### System Prompt

The system prompt is defined once as a constant in `AnthropicClient` or a dedicated `Prompts.swift` file. It must never be constructed dynamically. See `docs/design.md` section 7.2 for the exact system prompt text.

---

## Protocol Corpus

`Resources/protocols.json` is bundled with the app. It is read-only at runtime — never write to it. Load it once at app startup and cache in memory.

**ProtocolMatcher** evaluates a `HealthSummary` against fixed condition flag rules (see `docs/design.md` section 6.2) and returns the top 4-5 matching protocols sorted by effort level (lower effort first on low-readiness days).

Condition flags are a `Set<String>`. Mapping logic is deterministic — same inputs always produce the same flags.

---

## Goal System

### Goal Modes

- `target` — user set a numeric target with optional timeframe. Has phase progression.
- `maintain` — baseline is the target. Safe zone violations only. No phases.

### Safe Zone Evaluation

Runs every time app opens. Results stored in memory (not persisted — recomputed each time).

```swift
enum SafeZoneStatus {
    case normal
    case warning
    case alert
}
```

**HRV uses relative thresholds** (percentage of personal baseline).
**RHR and respiratory rate use absolute thresholds** (fixed bpm / breaths per min values).

### Phase Advancement

Evaluated weekly. Phase advances when 7-day average is within or above sub-target range for 2 consecutive weekly snapshots. Phase advancement triggers an in-app notification (local, not push).

### Goal Conflict Detection

Check on goal save. See `docs/design.md` section 5.4 for conflict patterns. Display a warning sheet — do not block saving.

---

## Notifications

Use `UNUserNotificationCenter`. Request authorization at onboarding.

Three notification types:

| Type | Schedule | Trigger |
|---|---|---|
| Morning Readiness | Daily at user's wake time | Calendar trigger |
| Weekly Coaching | Sunday at 8am | Calendar trigger |
| Activity Nudge | Daily at 5pm | Calendar trigger (cancelled if activity on target) |

For Activity Nudge: schedule at 5pm with a `UNNotificationRequest`. Before scheduling, check yesterday/today's HealthKit data. If all activity metrics are above `alert_below` thresholds, call `removePendingNotificationRequests` instead.

**No background HealthKit for notifications.** The 5pm notification is pre-evaluated and scheduled during app foreground.

---

## Xcode & Build

- Xcode is available on the local Mac
- Target: iOS 17.0+
- Deployment: personal device only (no App Store submission in v1)
- Signing: personal team / free developer account is fine
- Swift Package Manager for any dependencies (none expected in v1)
- No storyboards — SwiftUI only
- Enable HealthKit capability in Xcode project settings (required for HealthKit entitlement)

### Config.plist Setup

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "...">
<plist version="1.0">
<dict>
    <key>AnthropicAPIKey</key>
    <string>sk-ant-YOUR_KEY_HERE</string>
    <key>DefaultModel</key>
    <string>claude-haiku-4-5-20251001</string>
    <key>AnalysisModel</key>
    <string>claude-sonnet-4-6</string>
</dict>
</plist>
```

**Config.plist must be in .gitignore.** Verify this before the first commit.

---

## Coding Standards

### Swift Style

- Use `async/await` throughout. No completion handlers except where HealthKit requires them (wrap immediately).
- Use `@MainActor` on ViewModels. Use actors for services that handle shared state (AnthropicClient, TrendStore writes).
- Prefer `struct` over `class` for models. Use `class` only for ObservableObject ViewModels.
- Use `@Observable` macro (iOS 17) for ViewModels rather than `ObservableObject` + `@Published`.
- Error handling: use typed errors (`enum AppError: Error`), never swallow errors silently, surface them to the user via a simple alert.

### File Conventions

- One type per file
- File name matches type name
- Extensions in `Extensions/` folder, named `TypeName+Purpose.swift`

### JSON Persistence Pattern

All JSON stores follow this pattern:

```swift
actor TrendStore {
    private var data: TrendStoreData
    private let fileURL: URL
    
    func save() async throws {
        let encoded = try JSONEncoder().encode(data)
        try encoded.write(to: fileURL, options: .atomic)
    }
    
    static func load() async throws -> TrendStore {
        // load from disk or create fresh if not found
    }
}
```

Always write with `.atomic` option to prevent partial writes.

### No Force Unwraps

Zero force unwraps (`!`) in production code paths. Use `guard let` or `if let`. The only acceptable force unwrap is in `HKObjectType` initialization where the identifier is a compile-time constant and failure is a programming error, not a runtime condition.

---

## Development Phases

Follow this sequence strictly. Do not skip ahead.

**Phase 1 — Data Foundation (Week 1)**
Goal: HealthKit queries working, TrendStore reading/writing with real data.
Done when: Can print a complete HealthSummary struct with real values to console.

**Phase 2 — Prompt Engineering (Week 2)**
Goal: Context builder producing correct LLM context, morning card JSON output is reliable.
Done when: 5 different hardcoded health scenarios all produce correct, well-reasoned morning card responses.

**Phase 3 — Protocol Corpus (Week 3)**
Goal: protocols.json authored (~50 entries), ProtocolMatcher selecting correct protocols per scenario.
Done when: Correct protocols selected for all 5 test scenarios from Phase 2.

**Phase 4 — Morning Card + Notifications (Week 4)**
Goal: Full morning flow end-to-end with real data and UI.
Done when: Morning notification fires, tap opens app, real HealthKit data flows through to a rendered morning card.

**Phase 5 — Goal System (Week 5)**
Goal: Goal setup UI, safe zone evaluation, progress store, HRV phase model.
Done when: Can set HRV goal, see Phase 1 plan, see weekly snapshot computed correctly.

**Phase 6 — Progress View + Weekly Review + Chat (Week 6)**
Goal: Complete app loop.
Done when: Weekly review generates meaningful coaching output, chat answers ad-hoc questions correctly.

---

## Known Constraints & Edge Cases

**Always handle these explicitly — do not leave as TODO:**

1. **Cold baseline (< 7 days data):** Use population reference ranges. Tell LLM baseline is cold. Do not show pace assessment on Progress tab.

2. **Missing metrics (nil values):** Log the missing metric in context block as "not available." Never pass null, zero, or empty string to LLM as if it were real data.

3. **HealthKit permission denied for specific metric:** Handle gracefully. Show "data unavailable" in relevant UI sections. Do not crash or hide the section entirely.

4. **LLM JSON parse failure:** Fall back to displaying raw LLM response text in the morning card. Log the parse error. Do not crash.

5. **API call failure (network, rate limit, invalid key):** Show a user-friendly error in the morning card area with a retry button. Never show raw API error messages to the user.

6. **First app launch (no stored data):** TrendStore, GoalStore, and ProgressStore must initialize with empty/default values, not crash on missing files.

7. **Apple Watch not worn:** HRV and sleep data will be absent. Handle as nil metrics case (rule 2 above).

---

## What NOT to Build in v1

Do not implement any of these even if they seem useful:

- Background HealthKit delivery or observer queries
- iCloud or any cloud sync
- User authentication or profiles
- VO2 Max goals (data too infrequent)
- Sport-specific metrics
- In-app purchases or subscription logic
- Any network calls other than Anthropic API
- Web views
- CoreData (use JSON files)
- Charts framework for sparklines — implement a simple custom SwiftUI shape

---

## Reference Documents

- Full design specification: `docs/design.md`
- Anthropic API docs: https://docs.anthropic.com
- HealthKit documentation: https://developer.apple.com/documentation/healthkit
- Human Interface Guidelines: https://developer.apple.com/design/human-interface-guidelines
