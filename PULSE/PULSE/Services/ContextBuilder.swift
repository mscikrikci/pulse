import Foundation

struct ContextBuilder {

    // MARK: - Morning Card Context

    static func buildMorningContext(
        summary: HealthSummary,
        trends: TrendStoreData,
        goals: String = "No active goals set.",
        protocols: String = "No protocols matched.",
        events: [String] = []
    ) -> String {
        let dateStr = formatDate(summary.date)
        let status = baselineStatusLabel(days: trends.baselineDataDays)
        let b = trends.baselines

        var lines: [String] = []
        lines.append("=== HEALTH SUMMARY — \(dateStr) ===")
        lines.append("")
        lines.append("Baseline Status: \(status)")
        lines.append("")
        lines.append("Last Night's Data:")
        lines.append(sleepLine(summary, baselines: b))
        lines.append(hrvLine(summary, baselines: b))
        lines.append(rhrLine(summary, baselines: b))
        lines.append(respRateLine(summary, baselines: b))
        lines.append("")
        lines.append("Activity (Yesterday):")
        lines.append(caloriesLine(summary, baselines: b))
        lines.append(stepsLine(summary, baselines: b))
        lines.append("")
        lines.append("Mobility & Fitness (rolling averages):")
        lines.append(vo2MaxLine(summary, baselines: b))
        lines.append(walkingSpeedLine(summary, baselines: b))
        lines.append(walkingHRLine(summary, baselines: b))
        lines.append(stairSpeedLine(summary))
        lines.append(cardioRecoveryLine(summary))
        lines.append("")
        lines.append("Current Session:")
        lines.append(timeOfDayLine(summary))
        lines.append(awakeTimeLine(summary))
        lines.append(todayActivityLine(summary))
        lines.append("")
        lines.append("Today's Log:")
        if events.isEmpty {
            lines.append("- No subjective events reported")
        } else {
            lines.append("- Reported: \(events.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("=== GOALS & PROGRESS ===")
        lines.append(goals)
        lines.append("")
        lines.append("=== AVAILABLE PROTOCOLS ===")
        lines.append(protocols)
        lines.append("")
        lines.append("=== MODE ===")
        lines.append("morning_card")

        return lines.joined(separator: "\n")
    }

    // MARK: - Agent Frame (Phase B)

    /// Lean orientation block sent as the first message in every agentic run.
    /// The agent pulls all data it needs via tools — this just provides date, status, event context,
    /// and any accumulated long-term memory from previous sessions.
    static func buildAgentFrame(
        baselineStatus: BaselineStatus,
        goalCount: Int,
        todayEvents: [String],
        memory: MemoryContext = .empty,
        dailyTasks: [DailyTask] = []
    ) -> String {
        let dateStr = Date().formatted(date: .complete, time: .shortened)
        let eventsStr = todayEvents.isEmpty ? "none" : todayEvents.joined(separator: ", ")

        var lines = [
            "=== PULSE AGENT — \(dateStr) ===",
            "",
            "Baseline Status: \(baselineStatus.description)",
            "Active Goals: \(goalCount)",
            "Today's Reported Events: \(eventsStr)"
        ]

        if !dailyTasks.isEmpty {
            lines.append("")
            lines.append("=== TODAY'S ACTIONS ===")
            for task in dailyTasks {
                let check = task.isCompleted ? "✓" : "○"
                let tag = task.source == "morning_card" ? "morning" : "check-in"
                lines.append("\(check) [\(tag)] \(task.title)")
            }
        }

        if !memory.isEmpty {
            if let summary = memory.identitySummary {
                lines.append("")
                lines.append("=== WHAT I KNOW ABOUT YOU ===")
                lines.append(summary)
            }

            if !memory.recentEpisodic.isEmpty {
                lines.append("")
                lines.append("=== RECENT NOTABLE EVENTS ===")
                for e in memory.recentEpisodic {
                    lines.append("- [\(e.date)] \(e.content)")
                }
            }

            if !memory.patterns.isEmpty {
                lines.append("")
                lines.append("=== YOUR PATTERNS ===")
                for p in memory.patterns {
                    lines.append("- \(p.description)")
                }
            }
        }

        return lines.joined(separator: "\n")
    }

    // MARK: - Chat Context

    static func buildChatContext(
        summary: HealthSummary,
        trends: TrendStoreData,
        goals: String = "No active goals set.",
        events: [String] = [],
        userMessage: String
    ) -> String {
        var base = buildMorningContext(summary: summary, trends: trends, goals: goals, events: events)
        base = base.replacingOccurrences(of: "=== MODE ===\nmorning_card", with: "=== USER QUESTION ===\n\(userMessage)")
        return base
    }

    // MARK: - Metric Lines

    private static func sleepLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let hours = s.sleepHours else {
            return "- Sleep: not available (Watch not worn or data not recorded)"
        }
        var line = "- Sleep: \(String(format: "%.1f", hours))h"
        if let avg = b.sleepHours7DayAvg {
            let delta = hours - avg
            let sign = delta >= 0 ? "+" : ""
            line += " (your 7d avg: \(String(format: "%.1f", avg))h | delta: \(sign)\(String(format: "%.1f", delta))h)"
        }
        if let eff = s.sleepEfficiency {
            line += " | efficiency: \(Int(eff * 100))%"
            if let avgEff = b.sleepEfficiency30DayAvg {
                line += " vs your avg \(Int(avgEff * 100))%"
            }
        }
        return line
    }

    private static func hrvLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let hrv = s.hrv else {
            return "- HRV: not available (Watch not worn or data not recorded)"
        }
        var line = "- HRV: \(String(format: "%.0f", hrv))ms"
        if let avg7 = b.hrv7DayAvg, let avg30 = b.hrv30DayAvg {
            let pct = ((hrv - avg7) / avg7) * 100
            let sign = pct >= 0 ? "+" : ""
            line += " (7d avg: \(String(format: "%.0f", avg7))ms | 30d avg: \(String(format: "%.0f", avg30))ms | delta: \(sign)\(String(format: "%.0f", pct))% from 7d avg)"
        }
        return line
    }

    private static func rhrLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let rhr = s.restingHR else {
            return "- Resting HR: not available (Watch not worn or data not recorded)"
        }
        var line = "- Resting HR: \(String(format: "%.0f", rhr))bpm"
        if let avg = b.restingHR30DayAvg {
            let delta = rhr - avg
            let sign = delta >= 0 ? "+" : ""
            line += " (30d avg: \(String(format: "%.0f", avg))bpm | delta: \(sign)\(String(format: "%.0f", delta))bpm)"
        }
        return line
    }

    private static func respRateLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let resp = s.respiratoryRate else {
            return "- Respiratory Rate: not available (Watch not worn or data not recorded)"
        }
        var line = "- Respiratory Rate: \(String(format: "%.1f", resp)) breaths/min"
        if let avg = b.respiratoryRate30DayAvg {
            let delta = resp - avg
            let sign = delta >= 0 ? "+" : ""
            line += " (30d avg: \(String(format: "%.1f", avg)) | delta: \(sign)\(String(format: "%.1f", delta)))"
        }
        return line
    }

    private static func caloriesLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let cal = s.activeCalories else {
            return "- Active Calories: not available"
        }
        var line = "- Active Calories: \(Int(cal)) kcal"
        if let avg = b.activeCalories7DayAvg {
            line += " (7d avg: \(Int(avg)) kcal)"
        }
        return line
    }

    private static func stepsLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let steps = s.steps else {
            return "- Steps: not available"
        }
        var line = "- Steps: \(steps)"
        if let avg = b.steps7DayAvg {
            line += " (7d avg: \(Int(avg)))"
        }
        return line
    }

    private static func vo2MaxLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let v = s.vo2Max else {
            return "- VO2 Max: not available (requires Apple Watch outdoor workout)"
        }
        var line = "- VO2 Max: \(String(format: "%.1f", v)) mL/(kg·min)"
        if let avg30 = b.vo2Max30DayAvg, let avg7 = b.vo2Max7DayAvg {
            let delta = avg7 - avg30
            let sign = delta >= 0 ? "+" : ""
            line += " (7d avg: \(String(format: "%.1f", avg7)) | 30d avg: \(String(format: "%.1f", avg30)) | trend: \(sign)\(String(format: "%.1f", delta)))"
        }
        return line
    }

    private static func walkingSpeedLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let v = s.walkingSpeed else {
            return "- Walking Speed: not available (requires iPhone with motion data)"
        }
        var line = "- Walking Speed: \(String(format: "%.2f", v)) m/s"
        if let avg30 = b.walkingSpeed30DayAvg {
            let delta = v - avg30
            let sign = delta >= 0 ? "+" : ""
            line += " (30d avg: \(String(format: "%.2f", avg30)) m/s | delta: \(sign)\(String(format: "%.2f", delta)) m/s)"
        }
        return line
    }

    private static func stairSpeedLine(_ s: HealthSummary) -> String {
        let up = s.stairAscentSpeed.map { "\(String(format: "%.2f", $0)) m/s" } ?? "n/a"
        let down = s.stairDescentSpeed.map { "\(String(format: "%.2f", $0)) m/s" } ?? "n/a"
        return "- Stair Speed: ascent \(up) | descent \(down)"
    }

    private static func walkingHRLine(_ s: HealthSummary, baselines b: Baselines) -> String {
        guard let v = s.walkingHeartRate else {
            return "- Walking Heart Rate: not available (requires Apple Watch during walks)"
        }
        var line = "- Walking Heart Rate: \(String(format: "%.0f", v)) bpm"
        if let avg30 = b.walkingHeartRate30DayAvg {
            let delta = v - avg30
            let sign = delta >= 0 ? "+" : ""
            line += " (30d avg: \(String(format: "%.0f", avg30)) bpm | delta: \(sign)\(String(format: "%.0f", delta)) bpm)"
        }
        return line
    }

    private static func cardioRecoveryLine(_ s: HealthSummary) -> String {
        guard let v = s.cardioRecovery else {
            return "- Cardio Recovery: not available (requires post-exercise Apple Watch measurement)"
        }
        return "- Cardio Recovery (1 min): \(String(format: "%.0f", v)) bpm drop"
    }

    // MARK: - Current Session Lines

    private static func timeOfDayLine(_ s: HealthSummary) -> String {
        let hour = Calendar.current.component(.hour, from: s.date)
        let period: String
        switch hour {
        case 5..<12:  period = "Morning"
        case 12..<17: period = "Afternoon"
        case 17..<21: period = "Evening"
        default:      period = "Night"
        }
        let tf = DateFormatter()
        tf.timeStyle = .short
        return "- Time: \(tf.string(from: s.date)) (\(period))"
    }

    private static func awakeTimeLine(_ s: HealthSummary) -> String {
        guard let wake = s.wakeTime else {
            return "- Awake since: not available (sleep data absent)"
        }
        let elapsed = s.date.timeIntervalSince(wake)
        guard elapsed > 0 else {
            return "- Awake since: just woke up"
        }
        let hours = Int(elapsed / 3600)
        let minutes = Int((elapsed.truncatingRemainder(dividingBy: 3600)) / 60)
        let tf = DateFormatter()
        tf.timeStyle = .short
        if hours > 0 {
            return "- Awake for: \(hours)h \(minutes)min (since \(tf.string(from: wake)))"
        } else {
            return "- Awake for: \(minutes)min (since \(tf.string(from: wake)))"
        }
    }

    private static func todayActivityLine(_ s: HealthSummary) -> String {
        let cal = s.todayCalories.map { "\(Int($0)) kcal" } ?? "not available"
        let steps = s.todaySteps.map { "\($0) steps" } ?? "not available"
        return "- Today so far: \(cal) active · \(steps)"
    }

    // MARK: - Helpers

    private static func baselineStatusLabel(days: Int) -> String {
        switch days {
        case 0..<7:
            return "insufficient data (\(days) day\(days == 1 ? "" : "s") of history — use population reference ranges, temper confidence)"
        case 7..<30:
            return "building (\(days) days of history — personal baselines exist but may still shift)"
        default:
            return "established (\(days) days of history — full personal baseline active)"
        }
    }

    private static func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateStyle = .full
        return f.string(from: date)
    }
}
