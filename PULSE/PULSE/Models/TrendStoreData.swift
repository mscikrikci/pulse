import Foundation

struct TrendStoreData: Codable, Sendable {
    var lastUpdated: Date
    var baselines: Baselines
    var history: [DayEntry]
    var baselineDataDays: Int
}

enum BaselineStatus: String, Codable, Sendable {
    case cold
    case building
    case established

    var description: String {
        switch self {
        case .cold:        return "cold (fewer than 7 days — use population references, temper confidence)"
        case .building:    return "building (7–29 days — personal baseline forming)"
        case .established: return "established (30+ days — full personal baseline active)"
        }
    }
}

struct Baselines: Codable, Sendable {
    var hrv7DayAvg: Double? = nil
    var hrv30DayAvg: Double? = nil
    var restingHR7DayAvg: Double? = nil
    var restingHR30DayAvg: Double? = nil
    var sleepHours7DayAvg: Double? = nil
    var sleepHours30DayAvg: Double? = nil
    var sleepEfficiency30DayAvg: Double? = nil
    var respiratoryRate30DayAvg: Double? = nil
    var activeCalories7DayAvg: Double? = nil
    var steps7DayAvg: Double? = nil
    // Mobility & fitness baselines
    var vo2Max30DayAvg: Double? = nil
    var vo2Max7DayAvg: Double? = nil
    var walkingSpeed30DayAvg: Double? = nil
    var walkingSpeed7DayAvg: Double? = nil
    var walkingHeartRate30DayAvg: Double? = nil
}

struct DayEntry: Codable, Sendable {
    let date: String               // "YYYY-MM-DD"
    var hrv: Double?
    var restingHR: Double?
    var sleepHours: Double?
    var sleepEfficiency: Double?
    var respiratoryRate: Double?
    var activeCalories: Double?
    var steps: Int?
    var alcoholReported: Bool?
    var events: [String]?          // user-reported: high_stress, fatigue, sadness, argument, anger, health_issue
    // Mobility & fitness
    var vo2Max: Double?
    var cardioRecovery: Double?
    var walkingHeartRate: Double?
    var walkingSpeed: Double?
    var stairAscentSpeed: Double?
    var stairDescentSpeed: Double?
}
