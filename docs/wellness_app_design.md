# Pulse — Personal Wellness Coaching App
## Design Document v0.1

---

## Table of Contents

1. [Product Vision](#1-product-vision)
2. [Scope — Prototype v1](#2-scope--prototype-v1)
3. [Architecture Overview](#3-architecture-overview)
4. [Data Layer](#4-data-layer)
5. [Goal & Alert System](#5-goal--alert-system)
6. [Protocol Corpus (RAG)](#6-protocol-corpus-rag)
7. [LLM Integration](#7-llm-integration)
8. [Notification System](#8-notification-system)
9. [UI Structure](#9-ui-structure)
10. [Progress & Coaching Layer](#10-progress--coaching-layer)
11. [Development Sequence](#11-development-sequence)
12. [Future Roadmap](#12-future-roadmap)

---

## 1. Product Vision

Pulse bridges the gap between raw health data and meaningful behavioral change. It operates across three time horizons simultaneously:

- **Today** — Am I recovered? What should I prioritize right now?
- **This week** — Are my habits consistent enough to expect progress?
- **The journey** — Am I trending toward my goals? What is the highest-leverage behavior to focus on?

Most wellness apps address only the first horizon. Pulse addresses all three through a conversational AI interface grounded in personal health data and evidence-based protocols (Huberman Lab corpus).

### Core Design Principles

**Outcome-oriented, not activity-oriented.** Goals are set on physiological outcomes (HRV, resting heart rate, respiratory rate). Activity metrics (steps, calories) are inputs that serve those outcomes — they generate nudges, not goals.

**Personal baseline over population norms.** All evaluations compare the user against their own rolling baseline. A "good" HRV is relative to that individual, not a population average.

**Minimal manual input.** The app infers as much as possible from HealthKit. Manual input is limited to one yes/no question per day (alcohol) and goal-setting screens.

**Conversational, not dashboard.** Insights are delivered through natural language. Data visualizations support the narrative rather than replace it.

**Not medical advice.** All suggestions are framed as performance optimization protocols sourced from Huberman Lab research. No diagnoses, no clinical claims.

---

## 2. Scope — Prototype v1

### In Scope

- HealthKit read access (sleep, HRV, resting HR, respiratory rate, active calories, steps)
- Local trend store (rolling baselines, progress history) — JSON files on device
- Goal setting for three outcome metrics: HRV, Resting Heart Rate, Sleep Respiratory Rate
- Activity alerts for steps and active calories (linked to outcome goals)
- Morning readiness alert — scheduled notification, on-demand analysis on tap
- Weekly coaching summary — scheduled Sunday notification, progress review on tap
- Ad-hoc chat interface — conversational questions about health data
- Huberman-based protocol corpus — local JSON, ~50 protocols at launch
- LLM integration via direct Anthropic API (personal API key in local config)
- Progress view — phase timeline, weekly trend, pace assessment per goal

### Out of Scope (v1)

- Backend, user accounts, cloud sync
- Background HealthKit processing
- Real-time alerts (safe zone violations trigger on app open, not background)
- VO2 Max goals (data too infrequent from Apple Watch for reliable tracking)
- Sport-specific metrics (swim pace, running power, cadence)
- Weight tracking
- Multiple user profiles

---

## 3. Architecture Overview

```
┌─────────────────────────────────────────────────────┐
│                     SwiftUI Layer                    │
│  Morning Card │ Chat Interface │ Goals │ Progress    │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│                  App Logic Layer                     │
│                                                      │
│  HealthKit       Context        Notification         │
│  Manager    →   Builder    →   Scheduler             │
│                    │                                 │
│  Trend Store  ─────┤                                 │
│  Goal Store   ─────┤                                 │
│  Protocol     ─────┘                                 │
│  Corpus                                              │
└──────────────────────┬──────────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────────┐
│               Anthropic API Layer                    │
│  AnthropicClient (claude-haiku-3-5 or sonnet-4-6)   │
│  API key from local Config.plist (gitignored)        │
└─────────────────────────────────────────────────────┘
```

### Technology Choices

| Component | Choice | Rationale |
|---|---|---|
| UI Framework | SwiftUI | Native, solo-developer speed |
| Local Storage | JSON files in Documents dir | Simple, debuggable, no CoreData overhead |
| HealthKit | Native HealthKit framework | Read-only, no write access needed |
| LLM | Anthropic API (direct) | Personal key in gitignored config |
| Default Model | claude-haiku-4-5 | Cost-efficient for daily calls; upgrade to sonnet for complex analysis |
| Protocol Corpus | Bundled JSON file | Updated via app upgrades, no CDN needed |

---

## 4. Data Layer

### 4.1 HealthKit Queries

All queries are on-demand (triggered by app open, notification tap, or chat message). No background fetching in v1.

**Metrics queried and their HealthKit identifiers:**

| Metric | HealthKit Type | Query Window | Aggregation |
|---|---|---|---|
| Sleep duration | HKCategoryTypeIdentifierSleepAnalysis | Last night | Sum of asleep stages |
| Sleep efficiency | HKCategoryTypeIdentifierSleepAnalysis | Last night | Asleep / time in bed |
| HRV (SDNN) | HKQuantityTypeIdentifierHeartRateVariabilitySDNN | Last night | Average during sleep |
| Resting Heart Rate | HKQuantityTypeIdentifierRestingHeartRate | Last night | Single daily sample |
| Respiratory Rate | HKQuantityTypeIdentifierRespiratoryRate | Last night | Average during sleep |
| Active Calories | HKQuantityTypeIdentifierActiveEnergyBurned | Yesterday | Sum |
| Steps | HKQuantityTypeIdentifierStepCount | Yesterday | Sum |

**HealthKit Authorization Request — requested permissions at onboarding:**
- All metrics above, read-only
- Authorization is per-metric; app must handle null gracefully for any metric the user declines

**Null handling rule:** If a metric is unavailable, it is excluded from the context block with an explicit note to the LLM: `"HRV: not available (Watch not worn or data not recorded)"`. The LLM must not infer from absent data.

### 4.2 Trend Store

**File location:** `Documents/trend_store.json`
**Updated:** Every time app opens (refreshes last 30 days)

```json
{
  "last_updated": "2026-02-27T08:14:00Z",
  "baselines": {
    "hrv_7day_avg": 61.2,
    "hrv_30day_avg": 58.3,
    "resting_hr_7day_avg": 53.1,
    "resting_hr_30day_avg": 52.1,
    "sleep_hours_7day_avg": 7.0,
    "sleep_hours_30day_avg": 7.1,
    "sleep_efficiency_30day_avg": 0.84,
    "respiratory_rate_30day_avg": 14.5,
    "active_calories_7day_avg": 580,
    "steps_7day_avg": 7800
  },
  "history": [
    {
      "date": "2026-02-26",
      "hrv": 61,
      "resting_hr": 52,
      "sleep_hours": 7.4,
      "sleep_efficiency": 0.87,
      "respiratory_rate": 14.2,
      "active_calories": 620,
      "steps": 8200,
      "alcohol_reported": false
    }
  ],
  "baseline_data_days": 24,
  "baseline_status": "building"
}
```

**`baseline_status` values:**
- `"cold"` — fewer than 7 days of data. Use population reference ranges. LLM must acknowledge thin data.
- `"building"` — 7-29 days. Baselines exist but may shift. LLM should note if trending.
- `"established"` — 30+ days. Full personal baseline. Normal operation.

### 4.3 Goal Store

**File location:** `Documents/goal_store.json`

```json
{
  "outcome_goals": [
    {
      "id": "hrv_goal_001",
      "metric": "hrv",
      "label": "Heart Rate Variability",
      "unit": "ms",
      "direction": "higher_is_better",
      "mode": "target",
      "target_value": 70,
      "baseline_at_set": 58.3,
      "set_date": "2026-02-27",
      "timeframe_weeks": 12,
      "current_phase": 1,
      "phase_start_date": "2026-02-27",
      "weekly_snapshots": [
        { "week": 1, "avg": 58.8, "pace": "on_track" }
      ],
      "safe_zone": {
        "type": "relative",
        "warning_pct": -15,
        "alert_pct": -25
      }
    },
    {
      "id": "rhr_goal_001",
      "metric": "resting_hr",
      "label": "Resting Heart Rate",
      "unit": "bpm",
      "direction": "lower_is_better",
      "mode": "maintain",
      "target_value": 52,
      "baseline_at_set": 52.1,
      "set_date": "2026-02-27",
      "timeframe_weeks": null,
      "current_phase": null,
      "phase_start_date": null,
      "weekly_snapshots": [],
      "safe_zone": {
        "type": "absolute",
        "warning_value": 57,
        "alert_value": 60
      }
    },
    {
      "id": "resp_goal_001",
      "metric": "respiratory_rate",
      "label": "Sleep Respiratory Rate",
      "unit": "breaths/min",
      "direction": "lower_is_better",
      "mode": "maintain",
      "target_value": 14.5,
      "baseline_at_set": 14.5,
      "set_date": "2026-02-27",
      "timeframe_weeks": null,
      "current_phase": null,
      "phase_start_date": null,
      "weekly_snapshots": [],
      "safe_zone": {
        "type": "absolute",
        "warning_value": 17.0,
        "alert_value": 19.0
      }
    }
  ],
  "activity_alerts": [
    {
      "metric": "active_calories",
      "label": "Active Calories",
      "daily_target": 600,
      "alert_below": 300,
      "linked_goal_id": "hrv_goal_001",
      "relationship_note": "Consistent daily movement supports HRV improvement. Target 500-700 calories — under-movement and overtraining both suppress HRV."
    },
    {
      "metric": "steps",
      "label": "Daily Steps",
      "daily_target": 8000,
      "alert_below": 4000,
      "linked_goal_id": "rhr_goal_001",
      "relationship_note": "Daily step volume correlates with resting HR reduction over weeks. Non-exercise activity is as important as formal training."
    }
  ]
}
```

### 4.4 Progress Store

**File location:** `Documents/progress_store.json`
Updated weekly (Sunday) and whenever goal phases advance.

```json
{
  "goal_progress": {
    "hrv_goal_001": {
      "phase_history": [
        {
          "phase": 1,
          "focus": "stabilize",
          "start_date": "2026-02-27",
          "end_date": null,
          "sub_target_range": [58.5, 60.5],
          "week_snapshots": [
            { "week": 1, "seven_day_avg": 58.8, "delta_from_baseline": 0.5, "pace": "on_track" }
          ],
          "status": "in_progress"
        }
      ],
      "overall_pace": "on_track",
      "projected_completion_date": "2026-05-30",
      "weeks_elapsed": 1,
      "weeks_total": 12
    }
  }
}
```

---

## 5. Goal & Alert System

### 5.1 Goal Modes

**Target mode** — user sets a desired value and optional timeframe. App tracks gap, generates phase-based progression plan, evaluates weekly pace.

**Maintain mode** — current baseline becomes the target. App monitors for safe zone violations and trend deviations. No phase progression needed.

### 5.2 Safe Zone Logic

Evaluated every time the app opens and when the morning card is generated.

**Relative thresholds (used for HRV):**
```
warning  = today_value < (personal_30day_avg × (1 + warning_pct/100))
alert    = today_value < (personal_30day_avg × (1 + alert_pct/100))
```

**Absolute thresholds (used for RHR and respiratory rate):**
```
warning  = today_value > warning_value
alert    = today_value > alert_value
```

**Resulting status values per metric:** `normal` / `warning` / `alert`

When any metric is in `alert` state, the morning card displays a prominent banner. The LLM context explicitly includes the violation and is instructed to prioritize addressing it over general optimization suggestions.

### 5.3 Activity Alert Logic

Evaluated once daily at 5pm via a scheduled notification. On notification tap, app queries yesterday/today's activity totals and compares to daily targets.

Alert fires (notification sent) only when:
- Activity metric is below `alert_below` threshold AND
- It is past 5pm (likely too late for today but relevant for tomorrow framing)

Alert copy references the linked outcome goal: *"You're at 2,400 steps today — consistent daily movement is one of the key inputs for your HRV goal."*

### 5.4 Goal Conflict Detection

When a user saves goals, the app checks for known conflict patterns:

| Conflict | Detection | Warning shown |
|---|---|---|
| High calorie target + HRV improvement goal | active_calories target > 800 AND hrv goal exists | "High daily calorie targets require adequate recovery. Start lower and adjust based on your HRV trend." |
| Aggressive RHR target + high step target | rhr target reduction > 10bpm in < 8 weeks | "Resting HR adaptations take 8-16 weeks. Consider extending your timeframe." |

### 5.5 HRV Progression Phases

Pre-authored for target mode HRV goals. The correct phase template is selected based on gap size (target - baseline):

**Phase templates (gap 8-20ms, 10-14 weeks):**

```
Phase 1 — Stabilize (weeks 1-3)
  Sub-target: baseline + 1-2ms
  Focus: Consistent sleep timing, alcohol elimination, morning sunlight
  Success signal: HRV variance reduces, no further decline

Phase 2 — Build (weeks 4-8)
  Sub-target: baseline + 4-7ms
  Focus: Zone 2 cardio 2-3x/week, daily NSDR or Yoga Nidra, cold exposure if tolerated
  Success signal: 7-day avg shows clear upward trend

Phase 3 — Optimize (weeks 9-14)
  Sub-target: baseline + gap (full target)
  Focus: Training load management, meal timing, alcohol strictly minimized
  Success signal: Consistent readings within 5ms of target
```

Phase advancement is automatic when the 7-day average crosses the sub-target range upper bound for 2 consecutive weeks.

---

## 6. Protocol Corpus (RAG)

### 6.1 Structure

**File location:** `Bundle/protocols.json` (bundled with app, updated via app releases)

Each protocol entry:

```json
{
  "id": "physiological_sigh",
  "title": "Physiological Sigh",
  "category": "stress_reduction",
  "tags": ["stress", "hrv", "nervous_system", "anxiety", "real_time"],
  "trigger_conditions": ["high_stress", "low_hrv", "elevated_rhr"],
  "duration_minutes": 1,
  "effort": "none",
  "timing": "anytime",
  "protocol": "Double inhale through the nose (first breath fills lungs ~80%, second sniff tops them off), followed by a long, slow exhale through the mouth. Repeat 1-3 times. Deflates the air sacs (alveoli) and activates the parasympathetic nervous system faster than any other volitional technique.",
  "why_it_works": "Collapsed alveoli trigger a stress response. The double inhale re-inflates them; the long exhale activates the vagal brake.",
  "source": "Huberman Lab — Controlling Stress in Real Time",
  "phase_relevance": ["hrv_phase_1", "hrv_phase_2"]
}
```

### 6.2 Retrieval Logic

Protocol retrieval is rule-based (no vector embeddings needed at this scale). The context builder:

1. Evaluates current health summary to flag active conditions from a fixed condition list
2. Filters protocols where any `trigger_conditions` entry matches a flagged condition
3. Sorts by `effort` (lower effort protocols prioritized on high-stress / low-HRV days)
4. Selects top 4-5 protocols
5. Passes protocol objects as structured JSON in the LLM context block

**Condition flag mapping:**

| Condition flag | Trigger criteria |
|---|---|
| `low_hrv` | HRV > 15% below 7-day average |
| `very_low_hrv` | HRV > 25% below 7-day average |
| `elevated_rhr` | RHR > 5bpm above 30-day average |
| `poor_sleep` | Sleep < 6.5h OR efficiency < 75% |
| `elevated_respiratory_rate` | Resp rate > 17 breaths/min |
| `high_stress` | low_hrv + elevated_rhr occurring together |
| `possible_illness` | elevated_respiratory_rate + elevated_rhr together |
| `well_recovered` | HRV within 5% of 30-day avg AND sleep > 7h |
| `peak_readiness` | HRV > 10% above 30-day avg AND sleep > 7h |

### 6.3 Initial Protocol Categories (~50 protocols at launch)

- Sleep quality and timing (10 protocols)
- Stress reduction and nervous system regulation (10 protocols)
- HRV and recovery optimization (8 protocols)
- Morning routines and circadian anchoring (8 protocols)
- Focus and cognitive performance (7 protocols)
- Movement and Zone 2 guidance (7 protocols)

---

## 7. LLM Integration

### 7.1 Configuration

**File:** `Config.plist` (gitignored, never committed)

```xml
<key>AnthropicAPIKey</key>
<string>sk-ant-...</string>
<key>DefaultModel</key>
<string>claude-haiku-4-5-20251001</string>
<key>AnalysisModel</key>
<string>claude-sonnet-4-6</string>
```

Haiku is used for morning cards and activity alerts. Sonnet is used for weekly coaching summaries and complex ad-hoc chat questions (those referencing multi-week trends).

### 7.2 System Prompt

```
You are Pulse, a personal wellness coaching assistant. You have access to the user's Apple Health data and evidence-based protocols from Huberman Lab research.

Your role:
- Help the user understand their recovery, readiness, and progress toward health goals
- Suggest specific, practical behavioral protocols grounded in the provided corpus
- Track and explain progress toward personal health goals across time horizons (today, this week, the journey)

Your constraints:
- You do not provide medical advice, diagnoses, or clinical recommendations
- All suggestions are framed as performance and wellness optimization
- Never suggest training through poor HRV or accumulated sleep debt
- When readiness conflicts with a fitness or training goal, always prioritize recovery first
- When data is limited (fewer than 14 days of baseline), explicitly acknowledge this and temper confidence accordingly
- When pace is "behind" on a goal, check whether habits are consistent before concluding the approach isn't working — distinguish "behind due to inconsistent habits" from "behind but habits are solid, adaptation takes time"

Your tone:
- Conversational and direct, not clinical
- Specific to the user's data — never generic
- Practical — always end with a concrete action
- Honest about uncertainty without being dismissive
```

### 7.3 Context Block Structure

The context builder assembles this block before every LLM call:

```
=== HEALTH SUMMARY — [date] ===

Baseline Status: established (34 days of data)

Last Night's Data:
- Sleep: 6.2h (your avg: 7.1h | delta: -0.9h | efficiency: 71% vs your avg 84%)
- HRV: 44ms (7-day avg: 61ms | 30-day avg: 58ms | delta: -28% from 7-day avg)
- Resting HR: 58bpm (30-day avg: 52bpm | delta: +6bpm above baseline)
- Respiratory Rate: 16.2 breaths/min (30-day avg: 14.5 | delta: +1.7)

Active Conditions: [very_low_hrv, elevated_rhr, poor_sleep]
Safe Zone Status: HRV — ALERT | RHR — WARNING | Resp Rate — WARNING

=== GOALS & PROGRESS ===

HRV Goal: 70ms target by May 27 (week 1 of 12)
  Current 7-day avg: 58.8ms | Baseline at goal set: 58.3ms
  Phase: 1 (Stabilize) | Sub-target: 58.5-60.5ms
  Pace: on_track | Trend: slight upward this week (good)
  Today's value: 44ms — significantly below baseline (likely acute, not chronic)

RHR Goal: maintain 52bpm
  Last night: 58bpm — WARNING (6bpm above baseline)
  Note: Combined with low HRV — likely under-recovered or early illness signal

Respiratory Rate: maintain 14.5 breaths/min
  Last night: 16.2 — WARNING (elevated, possible illness signal — monitor)

=== ACTIVITY (Yesterday) ===
- Active calories: 280 of 600 target (LOW — relevant to HRV goal)
- Steps: 3,200 of 8,000 target (LOW — relevant to RHR goal)

=== AVAILABLE PROTOCOLS ===
[Array of 4-5 matched protocol objects in JSON]

=== USER QUESTION / MODE ===
[morning_card | weekly_review | chat: "user message here"]
```

### 7.4 Morning Card Response Schema

For the morning card, the LLM is instructed to return structured JSON:

```json
{
  "readiness_level": "low",
  "headline": "Recovery priority today — protect tonight's sleep",
  "summary": "Two to three sentences grounded in specific numbers from the data.",
  "work_suggestion": "Short-form framing of what kind of cognitive work fits today.",
  "protocols": [
    {
      "id": "physiological_sigh",
      "reason": "One sentence on why this protocol fits today specifically."
    }
  ],
  "avoid_today": ["alcohol", "intense training", "late meals"],
  "one_focus": "The single most impactful thing to do today for tomorrow's recovery.",
  "goal_note": "One sentence on how today's readiness relates to the active goal journey."
}
```

`readiness_level` values: `"high"` / `"medium"` / `"low"` / `"alert"`

### 7.5 Weekly Review Response Schema

```json
{
  "week_number": 3,
  "week_summary": "Two to three sentences on what happened this week in data terms.",
  "goal_progress": {
    "hrv_goal_001": {
      "this_week_avg": 61.2,
      "delta_from_last_week": 2.1,
      "pace": "ahead",
      "phase_status": "completing phase 1 early",
      "recommendation": "One sentence on whether to advance phase or stay."
    }
  },
  "standout_positive": "What went well and why it likely contributed to outcomes.",
  "standout_concern": "What to watch next week and why.",
  "week_focus": "The single habit or behavior to prioritize next week.",
  "habit_consistency": {
    "consistent_wake_time": "5/7 days (inferred)",
    "alcohol_reported": "1 day"
  }
}
```

---

## 8. Notification System

### 8.1 Morning Readiness Notification

- **Type:** Local notification via `UNUserNotificationCenter`
- **Schedule:** User-configurable wake time (default 7:30am), fires daily
- **Content:** "Good morning. Your readiness summary is ready — tap to see today's report."
- **On tap:** App opens to Morning Card view, triggers HealthKit query + context build + LLM call
- **Loading state:** Show skeleton card while LLM call is in flight (typically 2-4 seconds)

### 8.2 Weekly Coaching Notification

- **Type:** Local notification
- **Schedule:** Sunday 8:00am (configurable)
- **Content:** "Your week [N] progress review is ready."
- **On tap:** App opens to Weekly Review view, triggers weekly context build + LLM call

### 8.3 Activity Nudge Notification

- **Type:** Local notification
- **Schedule:** 5:00pm daily
- **Content:** Generated at schedule time using latest HealthKit data. If activity is above `alert_below` threshold for all metrics, notification is cancelled (do not fire).
- **Example content:** "You're at 2,800 steps today — consistent movement supports your HRV goal. A 20-minute walk this evening would help."

### 8.4 Safe Zone Violation Banner

- **Trigger:** In-app, on app open
- **Condition:** Any metric in `alert` state
- **Display:** Persistent banner at top of home screen until dismissed or condition resolves
- **Does not use push notifications in v1**

---

## 9. UI Structure

### 9.1 Navigation

Tab bar with four tabs:

```
[ Today ] [ Progress ] [ Goals ] [ Chat ]
```

### 9.2 Today Tab

Primary daily surface. Three states:

**Pre-notification (before morning card generated):**
Last night's key metrics as a glanceable summary card. Prompt to "tap to generate today's readiness report" visible.

**Morning Card (after notification tap or manual generation):**
- Readiness level badge (HIGH / MEDIUM / LOW / ALERT) with color coding
- Headline and 2-3 sentence summary
- Work suggestion chip
- Protocol list (2-3 items with expandable detail)
- "Avoid today" tags
- One Focus — highlighted action item
- Goal note footer

**Alert State:**
If any metric is in `alert` state, the card is replaced by an alert banner at top:
- Metric name, current value, personal baseline, delta
- Brief LLM-generated context (why this matters)
- Suggested immediate action

**Alcohol check-in:**
Single card below the morning card: "Any alcohol yesterday?" YES / NO toggle. Saves to trend store. Used in weekly habit consistency tracking.

### 9.3 Progress Tab

Per-goal progress view. Scrollable list of active goals.

For each goal in **target mode:**
- Metric name, current value, target value, gap remaining
- Phase indicator: Phase 1 → 2 → 3 with current phase highlighted
- Timeframe progress bar (week N of week M)
- Pace badge: AHEAD / ON TRACK / BEHIND / STALLED
- Weekly sparkline (last 8 weeks of 7-day averages)
- Current phase focus and key habits

For each goal in **maintain mode:**
- Metric name, current value, target value
- Safe zone status badge
- 30-day trend sparkline
- No phase structure

### 9.4 Goals Tab

Goal management screen.

**Goal setup flow per metric:**
1. Shows metric name, current 30-day average, reference ranges
2. Mode selector: Target / Maintain
3. If target: value input with realistic range hint ("Research-backed range for 12 weeks: 62-68ms given your baseline")
4. If target: optional timeframe in weeks
5. Conflict detection warning if applicable
6. Save

**Activity alerts section:**
- Toggle and threshold input for steps and active calories
- Shows linked outcome goal with relationship explanation

### 9.5 Chat Tab

Conversational interface for ad-hoc questions.

- Standard message bubbles
- Each chat message automatically appends current health summary context (user doesn't see this, but LLM does)
- Suggested questions shown when chat is empty:
  - "How was my sleep this week compared to last?"
  - "Why might my HRV be lower than usual?"
  - "What should I focus on this week for my HRV goal?"
  - "I feel exhausted — what do you suggest?"
- Chat history not persisted across app sessions in v1

---

## 10. Progress & Coaching Layer

### 10.1 Pace Assessment

Computed weekly, stored in progress store. Compares actual 7-day average delta against expected weekly delta implied by the phase sub-target.

```
expected_weekly_delta = (phase_sub_target - baseline_at_phase_start) / phase_duration_weeks
actual_weekly_delta   = (this_week_avg - last_week_avg)

pace_ratio = actual_weekly_delta / expected_weekly_delta

if pace_ratio >= 1.2:  pace = "ahead"
if pace_ratio >= 0.7:  pace = "on_track"
if pace_ratio >= 0.3:  pace = "behind"
if pace_ratio < 0.3:   pace = "stalled"
```

**Important:** `stalled` requires 3 consecutive weeks of pace_ratio < 0.3 before the label is applied. A single bad week is not a stall.

### 10.2 Phase Advancement Logic

Phase advances automatically when:
- 7-day average is within or above the sub-target range for 2 consecutive weekly snapshots
- User is notified: "You've completed Phase 1 of your HRV goal — entering Phase 2: Build."

Phase does not advance when:
- Pace is "behind" or "stalled"
- User is in the middle of a streak of alert-level days (may indicate illness)

### 10.3 Weekly Coaching Context

The weekly review LLM call receives:
- All 7 daily entries from the past week
- 4-week rolling averages for trend context
- Goal progress with pace assessment
- Inferred habit consistency (wake time variance, alcohol reports)
- Which phase each goal is in and what the phase focus is
- Previous week's "one focus" recommendation (to evaluate if it was acted on, inferred from data where possible)

The LLM is instructed to: prioritize explaining *why* metrics moved (or didn't) over simply reporting the numbers, identify the single highest-leverage habit for next week, and advance or hold phases with explicit rationale.

---

## 11. Development Sequence

### Week 1 — Data Foundation

- HealthKit integration: request permissions, query all metrics
- Trend store: JSON read/write, rolling average computation
- Verify real data flows correctly with actual watch data
- Handle all null/missing metric cases
- Do not touch LLM yet

**Exit criteria:** Can print a clean health summary struct with real data to Xcode console.

### Week 2 — Prompt Engineering

- Build context builder (health summary → formatted context block)
- Hardcode a test health summary (simulate different states: good, poor, alert)
- Iterate prompts in Anthropic Console until morning card JSON output is exactly right
- Test edge cases: cold baseline, missing metrics, alert state

**Exit criteria:** Prompt reliably produces correct structured JSON for 5 different health scenarios.

### Week 3 — Protocol Corpus

- Author ~50 protocol entries in JSON format
- Build retrieval logic (condition flags → protocol filter → top 5 selection)
- Verify protocol selection makes sense for each test health scenario

**Exit criteria:** Correct protocols are selected for each of the 5 test scenarios.

### Week 4 — Morning Card and Notifications

- Wire HealthKit → context builder → LLM call → morning card UI
- Implement morning notification scheduling
- Implement activity nudge notification (5pm)
- Morning card UI: readiness badge, summary, protocols, one focus

**Exit criteria:** Full morning flow works end-to-end with real data.

### Week 5 — Goal System

- Goal store JSON: read/write
- Goal setup UI (Goals tab)
- Safe zone evaluation logic
- Progress store: weekly snapshot computation, pace assessment
- Phase progression model for HRV

**Exit criteria:** Can set an HRV goal, see phase 1 plan, and see a weekly snapshot computed correctly.

### Week 6 — Progress View and Weekly Review

- Progress tab UI: phase indicator, sparkline, pace badge
- Weekly review notification
- Weekly review LLM call with full coaching context
- Chat tab: ad-hoc questions with health context injection

**Exit criteria:** Full app loop works end-to-end. Weekly review generates meaningful coaching output.

---

## 12. Future Roadmap

### Near-term (v1.1 — v1.3)

- VO2 Max goal support (once data frequency is validated)
- Sport-specific goals: running cadence, Zone 2 HR target, swim pace
- Weight tracking goal (linked to RHR and HRV outcomes)
- Expanded protocol corpus (100+ protocols)
- Richer sleep stage analysis (deep sleep and REM percentages from HealthKit)

### Medium-term (v2)

- Background HealthKit anchored queries for real-time safe zone alerts
- iCloud sync for multi-device support (keeping local-first architecture)
- Apple Watch complication: daily readiness score
- Widget: morning readiness card on home screen without opening app

### Architecture evolution

- Personal baseline exceptions (user can flag periods as anomalous — illness, travel, unusual training block — to exclude from baseline computation)
- Multiple goal profiles (base training vs competition phase vs recovery phase)
- Optional lightweight backend for cross-device sync and baseline backup

---

## Appendix A — Reference Ranges

Used during cold baseline period and for goal-setting guidance.

| Metric | Low | Average | Good | Excellent |
|---|---|---|---|---|
| HRV (ms, adult) | < 30 | 40-60 | 60-80 | > 80 |
| Resting HR (bpm) | — | 60-80 | 50-60 | < 50 |
| Sleep duration (hours) | < 6 | 6-7 | 7-8 | 8-9 |
| Sleep efficiency (%) | < 75 | 75-84 | 85-90 | > 90 |
| Respiratory rate (sleep, br/min) | — | 12-20 | 12-16 | 12-14 |

Note: HRV ranges are illustrative. Personal baseline is always the primary reference once established.

## Appendix B — Huberman Protocol Categories (launch corpus)

**Sleep & Circadian (10 protocols)**
Morning sunlight exposure, consistent wake time, temperature manipulation for sleep onset, avoiding light after 10pm, caffeine timing (no caffeine after 12pm), NSDR / Yoga Nidra, magnesium glycinate timing, alcohol and sleep architecture, meal timing and sleep quality, sleep environment optimization.

**Stress & Nervous System (10 protocols)**
Physiological sigh, box breathing, cyclic hyperventilation (Wim Hof) for alertness, cold exposure for stress inoculation, visual field dilation for calm, social connection and oxytocin, journaling for stress processing, forward ambulation (walking) for bilateral brain stimulation, deliberate heat exposure, NSDR mid-day.

**HRV & Recovery (8 protocols)**
Zone 2 cardio 3x/week, deload weeks, HRV-guided training load decisions, cold/hot contrast therapy, alcohol elimination, nasal breathing during training, recovery nutrition timing, sleep debt repayment protocol.

**Morning & Circadian Anchoring (8 protocols)**
Morning sunlight + movement combo, cold shower for cortisol pulse, delayed caffeine (wait 90-120 min after waking), morning hydration, no phone first 30 min, temperature exposure on waking, anchor wake time including weekends, morning exercise timing.

**Focus & Cognitive (7 protocols)**
90-minute ultradian focus blocks, visual focus narrowing drill, non-sleep deep rest between focus blocks, strategic caffeine timing for focus, eliminating visual distraction during work, binaural beats for focus (40Hz), cold exposure for norepinephrine and focus.

**Movement & Zone 2 (7 protocols)**
Zone 2 definition and implementation (can hold a conversation), 150-180 min Zone 2 per week target, HIIT 1-2x/week maximum, non-exercise activity throughout day, resistance training and HRV considerations, deload frequency, VO2 max intervals (4x4 protocol).
