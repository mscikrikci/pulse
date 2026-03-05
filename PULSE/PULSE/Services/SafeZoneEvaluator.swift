import Foundation

enum SafeZoneStatus {
    case normal
    case warning
    case alert
}

struct SafeZoneResult {
    let goalId: String
    let metric: GoalMetric
    let status: SafeZoneStatus
    let currentValue: Double
    let thresholdLabel: String
}

struct SafeZoneEvaluator {

    static func evaluate(
        summary: HealthSummary,
        goals: [GoalDefinition],
        baselines: Baselines
    ) -> [SafeZoneResult] {
        goals.compactMap { goal in
            evaluate(goal: goal, summary: summary, baselines: baselines)
        }
    }

    static func evaluate(
        goal: GoalDefinition,
        summary: HealthSummary,
        baselines: Baselines
    ) -> SafeZoneResult? {
        let config = goal.safeZone

        switch goal.metric {
        case .hrv:
            guard let current = summary.hrv,
                  let baseline = baselines.hrv30DayAvg, baseline > 0 else { return nil }
            let pct = (current - baseline) / baseline * 100
            let status: SafeZoneStatus
            if let alertPct = config.alertPct, pct <= alertPct {
                status = .alert
            } else if let warnPct = config.warningPct, pct <= warnPct {
                status = .warning
            } else {
                status = .normal
            }
            return SafeZoneResult(goalId: goal.id, metric: .hrv, status: status,
                                  currentValue: current,
                                  thresholdLabel: "\(String(format: "%.0f", pct))% from 30d avg")

        case .restingHR:
            guard let current = summary.restingHR else { return nil }
            let status: SafeZoneStatus
            if let alertVal = config.alertValue, current >= alertVal {
                status = .alert
            } else if let warnVal = config.warningValue, current >= warnVal {
                status = .warning
            } else {
                status = .normal
            }
            return SafeZoneResult(goalId: goal.id, metric: .restingHR, status: status,
                                  currentValue: current,
                                  thresholdLabel: "\(String(format: "%.0f", current))bpm")

        case .respiratoryRate:
            guard let current = summary.respiratoryRate else { return nil }
            let status: SafeZoneStatus
            if let alertVal = config.alertValue, current >= alertVal {
                status = .alert
            } else if let warnVal = config.warningValue, current >= warnVal {
                status = .warning
            } else {
                status = .normal
            }
            return SafeZoneResult(goalId: goal.id, metric: .respiratoryRate, status: status,
                                  currentValue: current,
                                  thresholdLabel: "\(String(format: "%.1f", current)) br/min")
        }
    }
}
