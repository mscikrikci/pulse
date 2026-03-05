import Foundation

struct WeeklyReviewResponse: Codable {
    let weekLabel: String                       // e.g. "Mar 1 – Mar 7, 2026"
    let overallSummary: String                  // 2–3 sentence narrative of the week
    let metrics: [WeeklyMetricEntry]            // key biometric metrics with ranges
    let alerts: [WeeklyReviewAlert]             // warning/alert conditions (may be empty)
    let activitySummary: String                 // narrative on movement, calories, steps
    let goalProgress: [GoalProgressNote]        // one entry per active goal
    let keyInsights: [String]                   // 3–5 bullet observations
    let nextWeekPriorities: [String]            // 3–5 actionable items for next week
    let weekFocus: String                       // single most important behavior

    enum CodingKeys: String, CodingKey {
        case weekLabel           = "week_label"
        case overallSummary      = "overall_summary"
        case metrics
        case alerts
        case activitySummary     = "activity_summary"
        case goalProgress        = "goal_progress"
        case keyInsights         = "key_insights"
        case nextWeekPriorities  = "next_week_priorities"
        case weekFocus           = "week_focus"
    }
}

// MARK: - Metrics

struct WeeklyMetricEntry: Codable {
    let metric: String          // display name: "HRV", "Sleep", "Resting HR", "Respiratory Rate"
    let unit: String            // "ms", "hours", "bpm", "br/min"
    let avg: Double
    let min: Double
    let max: Double
    let trend: String           // "improving" | "stable" | "declining" | "worsening"
    let vsBaseline: String      // human-readable: "+4ms above 30-day baseline" or "at baseline"

    enum CodingKeys: String, CodingKey {
        case metric, unit, avg, min, max, trend
        case vsBaseline = "vs_baseline"
    }
}

// MARK: - Alerts

struct WeeklyReviewAlert: Codable {
    let metric: String
    let severity: String        // "warning" | "alert"
    let message: String         // one sentence
}

// MARK: - Goal Progress

struct GoalProgressNote: Codable {
    let metricLabel: String
    let thisWeekAvg: Double
    let deltaFromLastWeek: Double
    let pace: String            // "ahead" | "on_track" | "behind" | "stalled"
    let phaseStatus: String
    let recommendation: String

    enum CodingKeys: String, CodingKey {
        case metricLabel         = "metric_label"
        case thisWeekAvg         = "this_week_avg"
        case deltaFromLastWeek   = "delta_from_last_week"
        case pace
        case phaseStatus         = "phase_status"
        case recommendation
    }
}
