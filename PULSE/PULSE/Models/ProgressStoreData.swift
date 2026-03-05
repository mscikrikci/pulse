import Foundation

struct ProgressStoreData: Codable, Sendable {
    var goalProgress: [String: GoalProgress]

    enum CodingKeys: String, CodingKey {
        case goalProgress = "goal_progress"
    }

    static func empty() -> ProgressStoreData {
        ProgressStoreData(goalProgress: [:])
    }
}

struct GoalProgress: Codable, Sendable {
    var phaseHistory: [PhaseRecord]
    var overallPace: String
    var projectedCompletionDate: String?
    var weeksElapsed: Int
    var weeksTotal: Int?

    enum CodingKeys: String, CodingKey {
        case phaseHistory = "phase_history"
        case overallPace = "overall_pace"
        case projectedCompletionDate = "projected_completion_date"
        case weeksElapsed = "weeks_elapsed"
        case weeksTotal = "weeks_total"
    }
}

struct PhaseRecord: Codable, Sendable {
    var phase: Int
    var focus: String
    var startDate: String
    var endDate: String?
    var subTargetRange: [Double]
    var weekSnapshots: [PhaseSnapshot]
    var status: String              // "in_progress" | "completed"

    enum CodingKeys: String, CodingKey {
        case phase, focus
        case startDate = "start_date"
        case endDate = "end_date"
        case subTargetRange = "sub_target_range"
        case weekSnapshots = "week_snapshots"
        case status
    }
}

struct PhaseSnapshot: Codable, Sendable {
    var week: Int
    var sevenDayAvg: Double
    var deltaFromBaseline: Double
    var pace: String

    enum CodingKeys: String, CodingKey {
        case week
        case sevenDayAvg = "seven_day_avg"
        case deltaFromBaseline = "delta_from_baseline"
        case pace
    }
}
