# Pulse — Personal Wellness Intelligence

Pulse is an iOS app that turns your Apple Watch and iPhone health data into a daily coaching loop grounded in evidence-based science. It reads your biometrics, tracks where you are relative to your goals, and tells you the single most useful thing to do right now — not someday.

---

## The Problem It Solves

Wearables generate a lot of data. Most wellness content generates a lot of advice. Neither alone closes the gap between *knowing* and *doing*.

You might know that HRV reflects autonomic recovery. You might know that physiological sighs reduce stress. But on a Tuesday morning, looking at a number on your watch, you still don't know: *is today a push day or a rest day? What's the one thing I should actually do?*

Pulse closes that gap by:

1. **Contextualising your numbers** — comparing today's HRV, sleep, and recovery against your personal 7-day and 30-day baselines, not population averages
2. **Matching conditions to protocols** — using a curated corpus of Huberman Lab evidence-based interventions, selected based on what your body is showing today
3. **Providing a specific action** — one focus, not a list of ten; matched to your current readiness level and phase of a goal
4. **Learning over time** — remembering what it has observed about you, what correlations have shown up in your data, and what your current training emphasis is

The result is a daily morning card that functions like a brief from a health coach who has read your last 30 nights of data and knows what phase of your HRV goal you're in.

---

## Core Philosophy

- **Personal baseline over population average** — your resting HR at 52 bpm means something different to someone whose 30-day average is 50 vs. 60. Pulse always compares you to you.
- **Evidence, not opinion** — every protocol suggestion traces back to a specific Huberman Lab episode and a named physiological mechanism.
- **Closing the knowing–doing gap** — the output is always an action, not just an insight. The morning card produces one focus and a task list. The chat agent adds items directly to your Today list.
- **No cloud, no tracking** — all data lives on your device. There are no accounts, no analytics, no server.

---

## What Pulse Tracks

Pulse reads the following from Apple Health (read-only, never writes):

| Metric | What It Reflects |
|---|---|
| HRV (SDNN) | Autonomic nervous system recovery; stress and training load |
| Resting Heart Rate | Cardiovascular health; accumulated fatigue |
| Sleep (hours + efficiency) | Recovery quantity and quality |
| Respiratory Rate (sleep) | Illness early warning; nervous system state |
| Active Calories | Daily energy expenditure |
| Step Count | Movement and activity level |
| VO2 Max | Cardiorespiratory fitness trajectory |
| Cardio Recovery (1 min) | Fitness and autonomic function post-exercise |
| Walking Heart Rate Avg | Aerobic efficiency during daily activity |
| Walking Speed | Mobility and functional fitness |
| Stair Ascent / Descent Speed | Leg power and neuromuscular health |

All metrics are optional — if your Watch wasn't worn, those fields are shown as unavailable and the LLM is explicitly told data is absent, not zero.

---

## Features

### Morning Card

Generated each morning using today's health data, your personal baselines, active goals, and long-term memory from previous sessions. The card contains:

- **Readiness level** — high / medium / low / alert
- **Headline** — one-sentence read on your day
- **Summary** — what the data is showing and why
- **Work suggestion** — training or cognitive load guidance for today
- **Protocols** — 1–3 specific Huberman Lab interventions matched to your current condition
- **Avoid today** — concrete things to skip (high-intensity, alcohol, late caffeine, etc.)
- **One focus** — the single most important action
- **Goal note** — where you are in your active goals and what today means for them

The morning card also populates your **Today's Actions** task list so you can check items off during the day.

### Mid-Day Check-In

A short check-in at any point during the day that accounts for how much you've moved since the morning card, what you've logged, and how the day is going. It produces a brief observation, a concrete suggestion, and an optional protocol — and adds a task to your Today list. From any check-in you can tap **Explore in Chat** to ask follow-up questions in context.

### Chat

A conversational interface to your health data, powered by an agentic AI that can call tools to retrieve your trends, compute correlations, look up protocols, and add tasks to your Today list. Ask it anything: *why is my HRV lower this week?*, *how does my sleep correlate with my resting HR?*, *what should I focus on in Phase 2 of my goal?*

When the agent adds a protocol suggestion to your task list it will tell you, and it will show up on the Today tab immediately.

### Weekly Review

A deeper analysis run once a week that looks at 7 and 14-day trends, goal pace, and whether patterns are emerging in your data. The weekly review also updates the agent's **long-term memory** — writing episodic notes about what it observed and updating a compressed identity model that is injected into every future session.

### Goal Tracking

Set outcome goals for HRV, Resting HR, or Respiratory Rate. Pulse uses a three-phase progression model (Stabilize → Build → Optimize) and tracks your weekly 7-day average against phase sub-targets. When you hit two consecutive weeks at or above a phase sub-target, the phase advances automatically and you get a notification.

Goals have **safe zones** — metric thresholds that trigger warning or alert banners on the Today tab if your current readings fall outside them.

### Today's Actions

A task list populated automatically from the morning card's one-focus and protocol suggestions, updated by the check-in, and addable-to by the chat agent. Each task shows where it came from (morning card, check-in, or chat). Tap to mark complete.

### Memory Inspector

A debug view (Settings → Memory Inspector) showing everything the system has remembered about you: episodic events, identified patterns, and the current identity summary — the compressed model that is injected into every agent session.

---

## End-User Setup

### Requirements

- iPhone running iOS 17 or later
- Apple Watch (recommended — required for HRV, sleep, respiratory rate, cardio recovery, walking HR)
- Anthropic API key (free tier sufficient for personal use; get one at console.anthropic.com)

### First Launch

1. Grant HealthKit permissions when prompted — all metrics are requested at once
2. Go to **Settings** and enter your Anthropic API key
3. The app is immediately usable; baselines build over 7–30 days as data accumulates
4. During the first 7 days the baseline is "cold" — the morning card will use population reference ranges and will say so

### Daily Use

**Morning** — Open the Today tab and generate your morning card. Review the readiness level, read the summary, check your task list.

**During the day** — Check off tasks as you complete them. Log significant events (high stress, poor sleep subjectively, alcohol) in the Daily Log section.

**Mid-day or afternoon** — Run a check-in if you want a quick status read.

**Evening or next morning** — The daily log is cleared each day. Start fresh.

**Weekly** — Run the weekly review from the Today tab. It will update your goal pace, write to long-term memory, and give you a structured summary of the week.

---

## Developer Guide

### Codebase Overview

Pulse is a single-target SwiftUI app with no third-party dependencies. All data stays on device.

```
Pulse/
├── App/                    — Entry point, tab bar
├── Models/                 — Data structs + actor-based JSON stores
├── Services/               — HealthKit, Anthropic API, context builders, agent runner
├── Views/
│   ├── Today/              — Morning card, check-in, daily log, task list
│   ├── Chat/               — Agentic chat conversation
│   ├── Progress/           — Goal progress cards and sparklines
│   ├── Goals/              — Goal setup and activity alerts
│   └── Settings/           — API key, LLM debug log, memory inspector
└── Resources/
    └── protocols.json      — Bundled Huberman Lab protocol corpus
```

Full technical reference: see `docs/TECHNICAL.md`

### Quick-Start for Developers

1. Clone the repo
2. Open `PULSE.xcodeproj` in Xcode
3. Add a `Config.plist` to the project with:
   ```xml
   <key>AnthropicAPIKey</key><string>your-key-here</string>
   <key>DefaultModel</key><string>claude-haiku-4-5-20251001</string>
   <key>AnalysisModel</key><string>claude-sonnet-4-6</string>
   ```
4. Enable the HealthKit capability in the target's Signing & Capabilities tab
5. Build and run on a real device (HealthKit does not work on simulator)

`Config.plist` is gitignored. Never commit it.

### Key Extension Points

**Adding a new health metric**

1. Add the `HKObjectType` to `readTypes` in `HealthKitManager.swift`
2. Write a `fetch*()` method following the existing pattern
3. Add the field to `HealthSummary.swift`
4. Add it to `DayEntry` and `Baselines` in `TrendStoreData.swift`
5. Wire it into `TrendStore.update(with:)` and `computeBaselines()`
6. Add a context line in `ContextBuilder.buildMorningContext()`
7. Add it to `AgentTools` metric enums and `ToolExecutor.metricValue()` / `dayEntryToDict()`

**Adding a new protocol**

Edit `Resources/protocols.json`. Add an entry following the existing schema. The relevant fields are `trigger_conditions` (which condition flags activate it), `effort` (0–4), and `timing`. No code changes needed.

**Adding a new agent tool**

1. Add the tool definition to `AgentTools.definitions`
2. Add a handler method to `ToolExecutor`
3. Add the `case` to `ToolExecutor.execute(name:input:)`

**Changing prompts**

All prompts are in `Services/Prompts.swift` as string constants. Edit them there. Never construct prompts dynamically from user input.

**Changing safe zone thresholds**

Safe zone evaluation is in `TodayViewModel.evaluateSafeZones()`. Thresholds are plain constants in that function.

**Changing phase advancement logic**

Phase advancement criteria are in `ProgressStore.checkAdvancement()`. The three-phase template is in `HRVPhasePlan.phases()`.

### Debug Tools

- **LLM Log** — Long-press the tab bar for 2 seconds to open a full log of every API call: model, tokens, duration, tool calls, raw response
- **Memory Inspector** — Settings → Memory Inspector — shows all episodic memories, pattern memories, and the current identity summary
- All prompts are readable constants in `Prompts.swift`

### Models

Anthropic API models used:

| Task | Model | Reason |
|---|---|---|
| Morning card | claude-haiku-4-5-20251001 | Fast, cheap, runs daily |
| Check-in | claude-haiku-4-5-20251001 | Simple single-shot |
| Chat (simple) | claude-haiku-4-5-20251001 | Fast response |
| Chat (complex) | claude-sonnet-4-6 | Multi-week trend analysis |
| Weekly review | claude-sonnet-4-6 | Deep analysis, writes memory |

Model names are configurable in `Config.plist`.

---

## Limitations

- **No background data refresh** — all HealthKit queries are foreground, on-demand. The app reads data when you open it.
- **Apple Watch required for most metrics** — HRV, sleep staging, respiratory rate, cardio recovery, and walking HR all require an Apple Watch.
- **Baseline builds over time** — the first 7 days are "cold" and less personalised. Full personalisation takes 30 days.
- **No cloud sync** — data is device-local. If you delete the app, all stored history and memory is lost.
- **Anthropic API costs** — each morning card costs roughly $0.001–0.003 in API credits. Weekly reviews cost more (~$0.01–0.03). Personal use costs are negligible.

---

## Privacy

Pulse does not transmit your health data anywhere except to the Anthropic API to generate coaching responses. Health data is included in the text sent to the LLM in aggregate statistical form (averages, trends, percentages) — not as raw time-series. No data is stored by Anthropic beyond the API call itself (subject to Anthropic's data retention policy at docs.anthropic.com).

No analytics, no crash reporting, no third-party SDKs.

---

## Acknowledgements

Protocol content is derived from Huberman Lab podcast episodes and associated literature. This app is a personal tool and does not constitute medical advice. Consult a qualified healthcare professional for medical guidance.
