# Pulse — Build Session

## Status Legend
- `[ ]` Not started
- `[~]` In progress
- `[x]` Complete
- `[!]` Requires manual Xcode action

---

## Current Phase: Phase 6 — Progress View + Weekly Review + Chat

---

## Phase 0 — Xcode Project Scaffold
**Goal:** Compiling, running app shell before any real logic.

| # | Step | Status |
|---|------|--------|
| 0.1 | Create `Pulse.xcodeproj` in Xcode (iOS App, SwiftUI, iOS 17, bundle ID `com.personal.Pulse`) | `[x]` |
| 0.2 | Enable HealthKit capability (Signing & Capabilities tab in Xcode) | `[x]` |
| 0.3 | Add `NSHealthShareUsageDescription` to Info.plist in Xcode | `[x]` |
| 0.4 | Create directory structure under `Pulse/` | `[x]` |
| 0.5 | Create `.gitignore` (must include `Config.plist`) | `[x]` |
| 0.6 | Create `Config/Config.plist` with API key placeholder | `[x]` |
| 0.7 | Stub `App/PulseApp.swift` and `App/ContentView.swift` (4-tab TabView) | `[x]` |
| 0.8 | Create `Models/AppError.swift` with typed error enum | `[x]` |

**Exit criteria:** App builds and runs on simulator showing a blank 4-tab bar.

**Manual steps (0.1–0.3):** These require Xcode GUI. After Claude creates all files, open Xcode, create the project targeting the `Pulse/` directory, then enable HealthKit capability and add the HealthKit usage description string.

---

## Phase 1 — Data Foundation
**Goal:** Real HealthKit data flowing into a printed `HealthSummary` struct.

| # | Step | Status |
|---|------|--------|
| 1.1 | `Models/HealthSummary.swift` — all-optional metric struct | `[x]` |
| 1.2 | `Models/TrendStoreData.swift` — Codable inner struct matching JSON schema | `[x]` |
| 1.3 | `Models/TrendStore.swift` — actor with load/save/update/baselineStatus | `[x]` |
| 1.4 | `Services/HealthKitManager.swift` — requestAuthorization + 6 async queries | `[x]` |
| 1.5 | `Views/Onboarding/OnboardingView.swift` — first-launch HealthKit + notification permission screen | `[~]` |
| 1.6 | Wire app open → fetchTodaySummary → updateTrendStore → print to console | `[x]` |
| 1.7 | Handle all nil/missing metric cases in queries | `[x]` |

**Exit criteria:** Console prints a complete `HealthSummary` with real data from Apple Watch/phone.

---

## Phase 2 — Context Builder + LLM Integration
**Goal:** Morning card JSON reliably produced from real data and hardcoded test scenarios.

| # | Step | Status |
|---|------|--------|
| 2.1 | `Services/AnthropicClient.swift` — actor, REST call, typed error, Config.plist key read | `[x]` |
| 2.2 | `Services/Prompts.swift` — system prompt, morning card instruction, weekly review, chat instruction constants | `[x]` |
| 2.3 | `Models/MorningCardResponse.swift` — Codable struct + `ProtocolSuggestion` struct | `[x]` |
| 2.4 | `Services/ContextBuilder.swift` — assembles §7.3 context block, nil → "not available" text, baseline status | `[x]` |
| 2.5 | Build 5 hardcoded test `HealthSummary` scenarios (`#if DEBUG`) | `[x]` |
| 2.6 | Run each scenario through ContextBuilder → AnthropicClient → JSON parse; iterate until all 5 pass | `[x]` |

**Exit criteria:** All 5 test scenarios (peak, normal, low, alert, cold baseline) produce valid `MorningCardResponse` JSON.

---

## Phase 3 — Protocol Corpus
**Goal:** ~50 protocols in `protocols.json`, correct selection logic for all test scenarios.

| # | Step | Status |
|---|------|--------|
| 3.1 | `Models/WellnessProtocol.swift` — Codable struct matching JSON schema | `[x]` |
| 3.2 | Author `Resources/protocols.json` — ~50 entries across 6 categories | `[x]` |
| 3.3 | `Services/ProtocolMatcher.swift` — condition flag evaluator + retrieval logic | `[x]` |
| 3.4 | Verify correct protocol selection for all 5 Phase 2 test scenarios | `[x]` |

**Protocol categories (50 entries total):**
- Sleep quality and timing (10)
- Stress reduction and nervous system regulation (10)
- HRV and recovery optimization (8)
- Morning routines and circadian anchoring (8)
- Focus and cognitive performance (7)
- Movement and Zone 2 guidance (7)

**Exit criteria:** Correct protocols selected for all 5 test scenarios.

---

## Phase 4 — Morning Card UI + Notifications
**Goal:** Full morning flow working end-to-end with real data.

| # | Step | Status |
|---|------|--------|
| 4.1 | `Views/Today/TodayViewModel.swift` — @Observable, generateMorningCard, checkAlcohol, safeZoneAlerts | `[x]` |
| 4.2 | `Views/Today/TodayView.swift` — alert banner, morning card, alcohol check-in, generate button | `[x]` |
| 4.3 | `Views/Today/MorningCardView.swift` — readiness badge, headline, summary, protocols, avoid-today, one focus, goal note | `[x]` |
| 4.4 | `Views/Today/AlertBannerView.swift` — persistent banner for alert-state metrics | `[x]` |
| 4.5 | `Services/NotificationScheduler.swift` — morning (wake time), weekly (Sunday 8am), activity nudge (5pm, cancellable) | `[x]` |
| 4.6 | Loading skeleton state during LLM call (`redacted()` modifier) | `[x]` |
| 4.7 | Retry button on API failure; user-visible error, never raw API message | `[x]` |

**Exit criteria:** Tap notification → app opens → real data → rendered morning card.

---

## Phase 5 — Goal System
**Goal:** Goal setup, safe zone evaluation, weekly progress tracking, HRV phase model.

| # | Step | Status |
|---|------|--------|
| 5.1 | `Models/GoalStoreData.swift` — Codable struct matching §4.3 JSON schema | `[x]` |
| 5.2 | `Models/GoalStore.swift` — actor, load/save, goal CRUD | `[x]` |
| 5.3 | `Models/ProgressStoreData.swift` — Codable struct matching §4.4 JSON schema | `[x]` |
| 5.4 | `Models/ProgressStore.swift` — actor, load/save, weekly snapshot write | `[x]` |
| 5.5 | `Services/SafeZoneEvaluator.swift` — relative thresholds (HRV) + absolute thresholds (RHR, resp rate) | `[x]` |
| 5.6 | `Services/PaceCalculator.swift` — pace ratio formula, stalled requires 3 consecutive weeks | `[x]` |
| 5.7 | Phase advancement logic — 2 consecutive weeks at sub-target, local notification on advance | `[x]` |
| 5.8 | `Services/GoalConflictDetector.swift` — conflict patterns from §5.4, warning sheet (never blocks save) | `[x]` |
| 5.9 | `Views/Goals/GoalsView.swift` — list of active goals + activity alerts section | `[x]` |
| 5.10 | `Views/Goals/GoalSetupView.swift` — mode selector, value/timeframe input, range hint, conflict sheet | `[x]` |
| 5.11 | `Views/Goals/ActivityAlertView.swift` — toggle + threshold, linked goal explanation | `[x]` |

**Exit criteria:** Can set HRV goal, see Phase 1 plan, see weekly snapshot computed correctly.

---

## Phase 6 — Progress View + Weekly Review + Chat
**Goal:** Complete app loop.

| # | Step | Status |
|---|------|--------|
| 6.1 | `Views/Progress/SparklineView.swift` — custom Shape (no Charts framework), tappable points | `[x]` |
| 6.2 | `Views/Progress/GoalProgressCardView.swift` — target mode: phase steps, pace badge, sparkline; maintain mode: safe zone badge, trend line | `[x]` |
| 6.3 | `Views/Progress/ProgressView.swift` — scrollable goal list, cold baseline guard (hide pace) | `[x]` |
| 6.4 | `Models/WeeklyReviewResponse.swift` — Codable struct matching §7.5 schema | `[x]` |
| 6.5 | `Views/Today/WeeklyReviewViewModel.swift` — builds 7-day context, calls Sonnet, parses response | `[x]` |
| 6.6 | Weekly review UI — surfaced from Today tab on Sunday notification tap | `[x]` |
| 6.7 | `Views/Chat/ChatViewModel.swift` — in-memory history, health context injection, haiku/sonnet selection heuristic | `[x]` |
| 6.8 | `Views/Chat/ChatView.swift` — message list, text input, suggested questions | `[x]` |
| 6.9 | `Views/Chat/MessageBubbleView.swift` — user vs assistant styling | `[x]` |

**Exit criteria:** Weekly review generates meaningful coaching output. Chat answers questions with data-grounded responses.

---

## Edge Cases — Must Handle Explicitly (All Phases)

| # | Case | Where handled |
|---|------|---------------|
| E1 | Cold baseline < 7 days | ContextBuilder uses Appendix A ranges; Progress tab hides pace |
| E2 | Nil metric values | ContextBuilder emits "not available (Watch not worn or data not recorded)" |
| E3 | HealthKit permission denied per metric | Each query returns nil; UI shows "data unavailable" per section |
| E4 | LLM JSON parse failure | do/catch fallback to rawFallbackText; log parse error |
| E5 | API failure (network/rate limit/bad key) | User-visible error with retry button; never raw API message |
| E6 | First app launch, no stored files | All stores initialize with empty defaults, no crash |
| E7 | Apple Watch not worn | HRV + sleep nil → handled by E2 |

---

## Extensions (create as needed)

- `Extensions/Date+Extensions.swift`
- `Extensions/Double+Extensions.swift`

---

*Last updated: All 6 phases complete. App loop done.*
