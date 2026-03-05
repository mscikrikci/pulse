import Foundation

struct HealthSummary: Codable {
    let date: Date
    var hrv: Double?               // ms, nil if unavailable
    var restingHR: Double?         // bpm
    var sleepHours: Double?        // total hours
    var sleepEfficiency: Double?   // 0.0-1.0
    var respiratoryRate: Double?   // breaths/min during sleep
    var activeCalories: Double?    // kcal — yesterday's total
    var steps: Int?                // yesterday's total
    var wakeTime: Date?            // end of last sleep period (approximate wake-up time)
    var todayCalories: Double?     // active kcal from midnight to now
    var todaySteps: Int?           // steps from midnight to now

    // Mobility & fitness (added iOS 14+ metrics)
    var vo2Max: Double?            // mL/(kg·min) — most recent from last 90 days (Watch-estimated)
    var cardioRecovery: Double?    // bpm drop at 1 min post-exercise — most recent 30 days (Watch)
    var walkingHeartRate: Double?  // bpm average while walking — yesterday (Watch)
    var walkingSpeed: Double?      // m/s — 7-day rolling average (iPhone mobility)
    var stairAscentSpeed: Double?  // m/s — 7-day rolling average (iPhone mobility)
    var stairDescentSpeed: Double? // m/s — 7-day rolling average (iPhone mobility)
}
