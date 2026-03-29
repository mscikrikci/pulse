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
    case vo2Max = "vo2max"
    case cardioRecovery = "cardio_recovery"

    var label: String {
        switch self {
        case .hrv:             return "Heart Rate Variability"
        case .restingHR:       return "Resting Heart Rate"
        case .respiratoryRate: return "Sleep Respiratory Rate"
        case .vo2Max:          return "Cardio Fitness (VO2 Max)"
        case .cardioRecovery:  return "Cardio Recovery (1 min)"
        }
    }

    var unit: String {
        switch self {
        case .hrv:             return "ms"
        case .restingHR:       return "bpm"
        case .respiratoryRate: return "breaths/min"
        case .vo2Max:          return "mL/(kg·min)"
        case .cardioRecovery:  return "bpm drop"
        }
    }

    var direction: GoalDirection {
        switch self {
        case .hrv:             return .higherIsBetter
        case .restingHR:       return .lowerIsBetter
        case .respiratoryRate: return .lowerIsBetter
        case .vo2Max:          return .higherIsBetter
        case .cardioRecovery:  return .higherIsBetter
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
        case .vo2Max:
            // Alert if 7d avg drops >10% below 30d avg
            return SafeZoneConfig(type: "relative", warningPct: -8, alertPct: -12,
                                  warningValue: nil, alertValue: nil)
        case .cardioRecovery:
            // Alert if 1-min HR drop falls below these thresholds (lower drop = worse fitness)
            return SafeZoneConfig(type: "absolute_lower", warningPct: nil, alertPct: nil,
                                  warningValue: 12, alertValue: 8)
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
        case .vo2Max:
            return "Average men: 35–40, women: 30–35 mL/(kg·min). Good: 45–50. Excellent: 50+. Aerobic adaptations take 8–16 weeks."
        case .cardioRecovery:
            return "Poor: <12 bpm drop. Average: 15–20. Good: 20–30. Excellent: >30 bpm. Improves with consistent cardio over 8–12 weeks."
        }
    }

    /// Arrow symbol reflecting improvement direction.
    var directionSymbol: String {
        switch self {
        case .hrv:             return "↑"
        case .restingHR:       return "↓"
        case .respiratoryRate: return "↓"
        case .vo2Max:          return "↑"
        case .cardioRecovery:  return "↑"
        }
    }

    /// Short phrase shown next to target field so the user knows which way to aim.
    var directionHint: String {
        switch self {
        case .hrv:             return "aim above this value"
        case .restingHR:       return "aim below this value"
        case .respiratoryRate: return "aim below this value"
        case .vo2Max:          return "aim above this value"
        case .cardioRecovery:  return "aim above this value"
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
