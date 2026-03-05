import Foundation

struct GoalStoreData: Codable, Sendable {
    var outcomeGoals: [GoalDefinition]
    var activityAlerts: [ActivityAlert]

    enum CodingKeys: String, CodingKey {
        case outcomeGoals = "outcome_goals"
        case activityAlerts = "activity_alerts"
    }

    static func empty() -> GoalStoreData {
        GoalStoreData(outcomeGoals: [], activityAlerts: [])
    }
}

// MARK: - Goal Definition

struct GoalDefinition: Codable, Identifiable, Sendable {
    var id: String
    var metric: GoalMetric
    var label: String
    var unit: String
    var direction: GoalDirection
    var mode: GoalMode
    var targetValue: Double
    var baselineAtSet: Double
    var setDate: String             // "YYYY-MM-DD"
    var timeframeWeeks: Int?
    var currentPhase: Int?
    var phaseStartDate: String?
    var weeklySnapshots: [WeeklySnapshot]
    var safeZone: SafeZoneConfig

    enum CodingKeys: String, CodingKey {
        case id, metric, label, unit, direction, mode
        case targetValue = "target_value"
        case baselineAtSet = "baseline_at_set"
        case setDate = "set_date"
        case timeframeWeeks = "timeframe_weeks"
        case currentPhase = "current_phase"
        case phaseStartDate = "phase_start_date"
        case weeklySnapshots = "weekly_snapshots"
        case safeZone = "safe_zone"
    }
}

enum GoalMetric: String, Codable, Sendable, CaseIterable {
    case hrv = "hrv"
    case restingHR = "resting_hr"
    case respiratoryRate = "respiratory_rate"

    var label: String {
        switch self {
        case .hrv:             return "Heart Rate Variability"
        case .restingHR:       return "Resting Heart Rate"
        case .respiratoryRate: return "Sleep Respiratory Rate"
        }
    }

    var unit: String {
        switch self {
        case .hrv:             return "ms"
        case .restingHR:       return "bpm"
        case .respiratoryRate: return "breaths/min"
        }
    }

    var direction: GoalDirection {
        switch self {
        case .hrv:             return .higherIsBetter
        case .restingHR:       return .lowerIsBetter
        case .respiratoryRate: return .lowerIsBetter
        }
    }

    var defaultSafeZone: SafeZoneConfig {
        switch self {
        case .hrv:
            return SafeZoneConfig(type: "relative", warningPct: -15, alertPct: -25,
                                  warningValue: nil, alertValue: nil)
        case .restingHR:
            return SafeZoneConfig(type: "absolute", warningPct: nil, alertPct: nil,
                                  warningValue: 57, alertValue: 60)
        case .respiratoryRate:
            return SafeZoneConfig(type: "absolute", warningPct: nil, alertPct: nil,
                                  warningValue: 17, alertValue: 19)
        }
    }

    var referenceRangeHint: String {
        switch self {
        case .hrv:
            return "Average adults: 40–60ms. Good: 60–80ms. Research-backed improvement range: +8–20ms over 10–14 weeks."
        case .restingHR:
            return "Average: 60–80bpm. Good: 50–60bpm. Excellent: below 50bpm. Adaptations take 8–16 weeks."
        case .respiratoryRate:
            return "Normal: 12–20 br/min. Good: 12–16. Optimal sleep: 12–14. Improvements take 4–8 weeks."
        }
    }

    /// Arrow symbol reflecting improvement direction.
    var directionSymbol: String {
        switch self {
        case .hrv:             return "↑"
        case .restingHR:       return "↓"
        case .respiratoryRate: return "↓"
        }
    }

    /// Short phrase shown next to target field so the user knows which way to aim.
    var directionHint: String {
        switch self {
        case .hrv:             return "aim above this value"
        case .restingHR:       return "aim below this value"
        case .respiratoryRate: return "aim below this value"
        }
    }
}

enum GoalMode: String, Codable, Sendable, CaseIterable {
    case target
    case maintain

    var label: String {
        switch self {
        case .target:   return "Target"
        case .maintain: return "Maintain"
        }
    }
}

enum GoalDirection: String, Codable, Sendable {
    case higherIsBetter = "higher_is_better"
    case lowerIsBetter = "lower_is_better"
}

// MARK: - Supporting Types

struct WeeklySnapshot: Codable, Sendable {
    var week: Int
    var avg: Double
    var pace: String
}

struct SafeZoneConfig: Codable, Sendable {
    var type: String
    var warningPct: Double?
    var alertPct: Double?
    var warningValue: Double?
    var alertValue: Double?

    enum CodingKeys: String, CodingKey {
        case type
        case warningPct = "warning_pct"
        case alertPct = "alert_pct"
        case warningValue = "warning_value"
        case alertValue = "alert_value"
    }
}

// MARK: - Activity Alert

struct ActivityAlert: Codable, Identifiable, Sendable {
    var metric: String
    var label: String
    var dailyTarget: Double
    var alertBelow: Double
    var linkedGoalId: String?
    var relationshipNote: String
    var isEnabled: Bool

    var id: String { metric }

    enum CodingKeys: String, CodingKey {
        case metric, label
        case dailyTarget = "daily_target"
        case alertBelow = "alert_below"
        case linkedGoalId = "linked_goal_id"
        case relationshipNote = "relationship_note"
        case isEnabled = "is_enabled"
    }
}
