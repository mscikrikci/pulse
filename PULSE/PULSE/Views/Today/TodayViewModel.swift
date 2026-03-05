import SwiftUI

// MARK: - Subjective Event Enum

enum SubjectiveEvent: String, CaseIterable {
    case highStress  = "high_stress"
    case fatigue     = "fatigue"
    case sadness     = "sadness"
    case argument    = "argument"
    case anger       = "anger"
    case healthIssue = "health_issue"

    var label: String {
        switch self {
        case .highStress:  return "High Stress"
        case .fatigue:     return "Fatigue"
        case .sadness:     return "Sadness"
        case .argument:    return "Argument"
        case .anger:       return "Anger"
        case .healthIssue: return "Health Issue"
        }
    }

    /// Maps this event to an existing ProtocolMatcher flag.
    var protocolFlag: String {
        switch self {
        case .highStress:  return "high_stress"
        case .fatigue:     return "poor_sleep"       // fatigue → recovery protocols
        case .sadness:     return "high_stress"      // same stress-reduction tools help
        case .argument:    return "high_stress"
        case .anger:       return "high_stress"
        case .healthIssue: return "possible_illness"
        }
    }
}

@Observable
@MainActor
class TodayViewModel {
    var morningCard: MorningCardResponse?
    var rawFallbackText: String?
    var isLoading = false
    var error: AppError?
    var safeZoneAlerts: [SafeZoneAlert] = []
    var alcoholCheckedToday = false
    var currentSummary: HealthSummary?
    var checkIn: CheckInResponse?
    var isCheckingIn = false

    // Daily log
    var dailyLogSubmitted = false
    var todayEvents: [String] = []          // raw values of SubjectiveEvent

    // Daily task list
    var dailyTasks: [DailyTask] = []

    private var trendStore: TrendStore?
    private var memoryStore: MemoryStore?
    private let healthKit = HealthKitManager()

    // MARK: - Bootstrap

    func bootstrap() async {
        do {
            try await healthKit.requestAuthorization()
            await NotificationScheduler.requestAuthorization()

            let store = try await TrendStore.load()
            let summary = try await healthKit.fetchTodaySummary()
            try await store.update(with: summary)
            trendStore = store
            currentSummary = summary
            let memory = await MemoryStore.load()
            await memory.pruneIfNeeded()
            memoryStore = memory

            // Restore today's morning card if it was already generated today.
            if let persisted = MorningCardStore.loadIfToday() {
                morningCard = persisted
                safeZoneAlerts = evaluateSafeZones(summary: summary, baselines: await store.baselines)
                // Tasks are restored separately from DailyTaskStore below — no re-population needed.
            }

            // Restore daily log state if already submitted today.
            let key = Self.todayDateKey()
            if UserDefaults.standard.string(forKey: "dailyLogDate") == key {
                dailyLogSubmitted = true
                alcoholCheckedToday = true
                todayEvents = UserDefaults.standard.stringArray(forKey: "dailyLogEvents") ?? []
            }

            // Restore today's task list.
            dailyTasks = DailyTaskStore.loadIfToday() ?? []

            NotificationScheduler.scheduleMorningNotification()
            NotificationScheduler.scheduleWeeklyReview()
            NotificationScheduler.evaluateAndScheduleActivityNudge(
                steps: summary.steps,
                activeCalories: summary.activeCalories
            )
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.healthKitQueryFailed(error.localizedDescription)
        }
    }

    // MARK: - Morning Card

    func generateMorningCard() async {
        guard let store = trendStore, let summary = currentSummary else {
            error = AppError.healthKitQueryFailed("Health data not loaded yet.")
            return
        }

        isLoading = true
        error = nil
        morningCard = nil
        rawFallbackText = nil

        let baselines = await store.baselines
        let baselineStatus = await store.baselineStatus
        let goalStore = try? await GoalStore.load()
        let progressStore = try? await ProgressStore.load()
        let goalCount = await goalStore?.goals.count ?? 0

        let memCtx = await memoryStore?.buildMemoryContext(relevantTags: Set(todayEvents)) ?? .empty
        let frame = ContextBuilder.buildAgentFrame(
            baselineStatus: baselineStatus,
            goalCount: goalCount,
            todayEvents: todayEvents,
            memory: memCtx
        )
        let initialMessage = frame + "\n\n" + Prompts.morningCardAgentInstruction

        do {
            let client = try AnthropicClient()

            var raw: String
            if let gs = goalStore, let ps = progressStore {
                let executor = ToolExecutor(trendStore: store, goalStore: gs, progressStore: ps,
                                            memoryStore: memoryStore)
                let runner = AgentRunner(client: client, executor: executor)
                let result = try await runner.run(
                    feature: .morningCard,
                    system: Prompts.agentSystem,
                    initialMessage: initialMessage,
                    model: "claude-haiku-4-5-20251001",
                    maxTokens: 1024
                )
                raw = result.text
            } else {
                // Fallback: single-shot with pre-built context if stores unavailable
                let storeData = await store.storeData
                let context = ContextBuilder.buildMorningContext(
                    summary: summary,
                    trends: storeData,
                    events: todayEvents
                )
                raw = try await client.completeMorningCard(context: context)
            }

            if let jsonData = raw.data(using: .utf8),
               let card = try? JSONDecoder().decode(MorningCardResponse.self, from: jsonData) {
                morningCard = card
                safeZoneAlerts = evaluateSafeZones(summary: summary, baselines: baselines)
                MorningCardStore.save(card)
                populateTasksFromMorningCard(card)
            } else {
                rawFallbackText = raw
            }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.apiFailure("Unexpected error. Please try again.")
        }

        isLoading = false
    }

    // MARK: - Mid-Day Check-In

    func generateCheckIn() async {
        isCheckingIn = true
        checkIn = nil

        // Refresh so check-in sees activity done since app was opened.
        if let fresh = try? await healthKit.fetchTodaySummary() {
            currentSummary = fresh
        }
        guard let summary = currentSummary else { isCheckingIn = false; return }

        // Evaluate condition flags and fetch matching protocols for the check-in
        let baselines = await trendStore?.baselines ?? Baselines()
        let matcher = ProtocolMatcher()
        let flags = matcher.evaluateFlags(summary: summary, baselines: baselines, userEvents: todayEvents)
        let matchedProtocols = matcher.matchByFlags(flags: flags, maxEffort: "medium")

        let context = morningCard != nil
            ? buildCheckInContext(card: morningCard!, summary: summary, protocols: matchedProtocols)
            : buildNoCardCheckInContext(summary: summary, protocols: matchedProtocols)

        do {
            let client = try AnthropicClient()
            let raw = try await client.completeCheckIn(context: context)
            if let data = raw.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(CheckInResponse.self, from: data) {
                checkIn = parsed
                addCheckInTask(parsed)
            }
        } catch {}

        isCheckingIn = false
    }

    /// Simplified check-in context when no morning card has been generated.
    private func buildNoCardCheckInContext(summary: HealthSummary, protocols: [WellnessProtocol] = []) -> String {
        let tf = DateFormatter(); tf.timeStyle = .short
        let hour = Calendar.current.component(.hour, from: summary.date)
        let period: String
        switch hour {
        case 5..<12:  period = "Morning"
        case 12..<17: period = "Afternoon"
        case 17..<21: period = "Evening"
        default:      period = "Night"
        }

        var lines: [String] = []
        lines.append("=== CURRENT STATE ===")
        lines.append("Time: \(tf.string(from: summary.date)) (\(period))")

        let calStr = summary.todayCalories.map { "\(Int($0)) kcal active" } ?? "not available"
        let stepsVal = summary.todaySteps ?? 0
        let stepsStr = stepsVal > 0 ? "\(stepsVal) steps" : "not available"
        lines.append("Activity so far: \(calStr) · \(stepsStr)")

        if stepsVal > 500 {
            let estWalkMin = stepsVal / 100
            lines.append("Estimated walking: ~\(estWalkMin) min of movement")
            if estWalkMin >= 10 {
                lines.append("IMPORTANT: The user has already completed ~\(estWalkMin) min of walking. Do NOT suggest another walk.")
            }
        }

        if !todayEvents.isEmpty {
            let eventLabels = todayEvents.map { SubjectiveEvent(rawValue: $0)?.label ?? $0 }.joined(separator: ", ")
            lines.append("Reported today: \(eventLabels)")
        }
        if !protocols.isEmpty {
            lines.append("")
            lines.append("=== AVAILABLE PROTOCOLS ===")
            for p in protocols {
                lines.append("- \(p.id): \(p.title) (\(p.durationMinutes) min)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private func buildCheckInContext(card: MorningCardResponse, summary: HealthSummary, protocols: [WellnessProtocol] = []) -> String {
        let tf = DateFormatter(); tf.timeStyle = .short
        let hour = Calendar.current.component(.hour, from: summary.date)
        let period: String
        switch hour {
        case 5..<12:  period = "Morning"
        case 12..<17: period = "Afternoon"
        case 17..<21: period = "Evening"
        default:      period = "Night"
        }

        var awakeDesc = "unknown"
        if let wake = summary.wakeTime {
            let elapsed = summary.date.timeIntervalSince(wake)
            if elapsed > 0 {
                let h = Int(elapsed / 3600), m = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
                awakeDesc = h > 0 ? "\(h)h \(m)min (since \(tf.string(from: wake)))" : "\(m)min"
            }
        }

        var lines: [String] = []
        lines.append("=== THIS MORNING'S CARD ===")
        lines.append("Readiness: \(card.readinessLevel)")
        lines.append("Headline: \(card.headline)")
        lines.append("Summary: \(card.summary)")
        lines.append("Work suggestion: \(card.workSuggestion)")
        lines.append("Morning focus: \(card.oneFocus)")
        lines.append("Morning protocols suggested: \(card.protocols.map(\.id).joined(separator: ", "))")
        lines.append("")
        lines.append("=== CURRENT STATE ===")
        lines.append("Time: \(tf.string(from: summary.date)) (\(period))")
        lines.append("Awake: \(awakeDesc)")

        // Raw activity numbers
        let calStr = summary.todayCalories.map { "\(Int($0)) kcal active" } ?? "not available"
        let stepsVal = summary.todaySteps ?? 0
        let stepsStr = stepsVal > 0 ? "\(stepsVal) steps" : "not available"
        lines.append("Activity so far: \(calStr) · \(stepsStr)")

        // Derive approximate walking duration from steps (≈100 steps/min at a normal walk pace)
        if stepsVal > 500, let wake = summary.wakeTime {
            let hoursAwake = summary.date.timeIntervalSince(wake) / 3600
            let estWalkMin = stepsVal / 100
            lines.append("Estimated walking: ~\(estWalkMin) min of movement (in \(String(format: "%.1f", hoursAwake))h since waking)")

            // Explicit completion signal for morning movement protocols
            if estWalkMin >= 10 {
                lines.append("IMPORTANT: The user has already completed ~\(estWalkMin) min of walking/movement since waking. Do NOT suggest another walk, outdoor stroll, or morning movement — that protocol is DONE.")
            }
        }

        if !todayEvents.isEmpty {
            let eventLabels = todayEvents.map { SubjectiveEvent(rawValue: $0)?.label ?? $0 }.joined(separator: ", ")
            lines.append("Reported today: \(eventLabels)")
        }
        if !protocols.isEmpty {
            lines.append("")
            lines.append("=== AVAILABLE PROTOCOLS ===")
            for p in protocols {
                lines.append("- \(p.id): \(p.title) (\(p.durationMinutes) min)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Daily Log

    func recordDailyLog(alcohol: Bool?, events: [String]) async {
        guard let store = trendStore else { return }
        if let a = alcohol {
            try? await store.recordAlcohol(a, for: Date())
            let key = Self.todayDateKey()
            UserDefaults.standard.set(key, forKey: "alcoholCheckedDate")
            alcoholCheckedToday = true
        }
        // Merge incoming events with already-logged events (union, not replace)
        let merged = Array(Set(todayEvents).union(Set(events)))
        if !merged.isEmpty {
            try? await store.recordEvents(merged, for: Date())
        }
        todayEvents = merged
        let key = Self.todayDateKey()
        UserDefaults.standard.set(key, forKey: "dailyLogDate")
        UserDefaults.standard.set(merged, forKey: "dailyLogEvents")
        dailyLogSubmitted = true
    }

    // MARK: - Daily Tasks

    /// Creates tasks from the morning card. Skips if morning-card tasks already exist for today.
    func populateTasksFromMorningCard(_ card: MorningCardResponse) {
        guard !dailyTasks.contains(where: { $0.source == "morning_card" }) else { return }
        var newTasks: [DailyTask] = []
        // One focus action
        newTasks.append(DailyTask(source: "morning_card", title: card.oneFocus,
                                  protocolId: nil, createdAt: Date()))
        // Protocol suggestions (use reason as the human-readable title)
        for p in card.protocols {
            newTasks.append(DailyTask(source: "morning_card", title: p.reason,
                                      protocolId: p.id, createdAt: Date()))
        }
        dailyTasks.append(contentsOf: newTasks)
        DailyTaskStore.save(dailyTasks)
    }

    /// Adds a task from a mid-day check-in. Replaces any prior check-in task to avoid duplicates.
    func addCheckInTask(_ checkIn: CheckInResponse) {
        dailyTasks.removeAll { $0.source == "check_in" }
        let task = DailyTask(source: "check_in", title: checkIn.suggestion,
                             protocolId: checkIn.protocolId, createdAt: Date())
        dailyTasks.append(task)
        DailyTaskStore.save(dailyTasks)
    }

    /// Toggles the completed state of a task and persists.
    func toggleTask(id: UUID) {
        if let idx = dailyTasks.firstIndex(where: { $0.id == id }) {
            dailyTasks[idx].isCompleted.toggle()
            DailyTaskStore.save(dailyTasks)
        }
    }

    /// Re-reads the task list from disk. Called when returning to Today tab so chat-added tasks appear.
    func refreshTasks() {
        if let fresh = DailyTaskStore.loadIfToday() {
            dailyTasks = fresh
        }
    }

    // MARK: - Helpers

    static func todayDateKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    // MARK: - Safe Zone Evaluation

    private func evaluateSafeZones(summary: HealthSummary, baselines: Baselines) -> [SafeZoneAlert] {
        var alerts: [SafeZoneAlert] = []

        if let hrv = summary.hrv, let avg30 = baselines.hrv30DayAvg, avg30 > 0 {
            let pct = (hrv - avg30) / avg30
            if pct < -0.25 {
                alerts.append(SafeZoneAlert(
                    metric: "HRV",
                    status: .alert,
                    current: "\(String(format: "%.0f", hrv))ms",
                    baseline: "\(String(format: "%.0f", avg30))ms",
                    delta: "\(String(format: "%.0f", pct * 100))%"
                ))
            } else if pct < -0.15 {
                alerts.append(SafeZoneAlert(
                    metric: "HRV",
                    status: .warning,
                    current: "\(String(format: "%.0f", hrv))ms",
                    baseline: "\(String(format: "%.0f", avg30))ms",
                    delta: "\(String(format: "%.0f", pct * 100))%"
                ))
            }
        }

        if let rhr = summary.restingHR {
            if rhr >= 60 {
                alerts.append(SafeZoneAlert(
                    metric: "Resting HR",
                    status: rhr >= 63 ? .alert : .warning,
                    current: "\(String(format: "%.0f", rhr))bpm",
                    baseline: "< 60bpm",
                    delta: "+\(String(format: "%.0f", rhr - 60))bpm"
                ))
            }
        }

        if let resp = summary.respiratoryRate {
            if resp >= 19 {
                alerts.append(SafeZoneAlert(
                    metric: "Respiratory Rate",
                    status: .alert,
                    current: "\(String(format: "%.1f", resp)) br/min",
                    baseline: "< 17 br/min",
                    delta: "+\(String(format: "%.1f", resp - 17)) br/min"
                ))
            } else if resp >= 17 {
                alerts.append(SafeZoneAlert(
                    metric: "Respiratory Rate",
                    status: .warning,
                    current: "\(String(format: "%.1f", resp)) br/min",
                    baseline: "< 17 br/min",
                    delta: "+\(String(format: "%.1f", resp - 17)) br/min"
                ))
            }
        }

        // Walking speed: < 1.0 m/s is clinically associated with reduced mobility and fall risk
        if let speed = summary.walkingSpeed {
            if speed < 0.8 {
                alerts.append(SafeZoneAlert(
                    metric: "Walking Speed",
                    status: .alert,
                    current: "\(String(format: "%.2f", speed)) m/s",
                    baseline: "> 1.0 m/s",
                    delta: "\(String(format: "%.2f", speed - 1.0)) m/s"
                ))
            } else if speed < 1.0 {
                alerts.append(SafeZoneAlert(
                    metric: "Walking Speed",
                    status: .warning,
                    current: "\(String(format: "%.2f", speed)) m/s",
                    baseline: "> 1.0 m/s",
                    delta: "\(String(format: "%.2f", speed - 1.0)) m/s"
                ))
            }
        }

        // Cardio recovery: < 12 bpm drop at 1 min post-exercise = poor cardiovascular fitness
        if let recovery = summary.cardioRecovery {
            if recovery < 8 {
                alerts.append(SafeZoneAlert(
                    metric: "Cardio Recovery",
                    status: .alert,
                    current: "\(String(format: "%.0f", recovery)) bpm drop",
                    baseline: "> 12 bpm",
                    delta: "\(String(format: "%.0f", recovery - 12)) bpm"
                ))
            } else if recovery < 12 {
                alerts.append(SafeZoneAlert(
                    metric: "Cardio Recovery",
                    status: .warning,
                    current: "\(String(format: "%.0f", recovery)) bpm drop",
                    baseline: "> 12 bpm",
                    delta: "\(String(format: "%.0f", recovery - 12)) bpm"
                ))
            }
        }

        // VO2 max: alert if 7-day trend is declining relative to 30-day baseline by > 5%
        if let vo2Max = summary.vo2Max,
           let avg7 = baselines.vo2Max7DayAvg, let avg30 = baselines.vo2Max30DayAvg, avg30 > 0 {
            let pct = (avg7 - avg30) / avg30
            if pct < -0.08 {
                alerts.append(SafeZoneAlert(
                    metric: "VO2 Max",
                    status: .alert,
                    current: "\(String(format: "%.1f", vo2Max)) mL/kg/min",
                    baseline: "\(String(format: "%.1f", avg30)) (30d avg)",
                    delta: "\(String(format: "%.0f", pct * 100))%"
                ))
            } else if pct < -0.05 {
                alerts.append(SafeZoneAlert(
                    metric: "VO2 Max",
                    status: .warning,
                    current: "\(String(format: "%.1f", vo2Max)) mL/kg/min",
                    baseline: "\(String(format: "%.1f", avg30)) (30d avg)",
                    delta: "\(String(format: "%.0f", pct * 100))%"
                ))
            }
        }

        return alerts
    }
}

// MARK: - Supporting Types

struct SafeZoneAlert: Identifiable {
    let id = UUID()
    let metric: String
    let status: AlertStatus
    let current: String
    let baseline: String
    let delta: String
}

enum AlertStatus {
    case warning, alert
}
