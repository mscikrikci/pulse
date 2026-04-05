import Foundation

// MARK: - HealthMetric

enum HealthMetric: String, CaseIterable, Sendable {
    // Recovery & Sleep
    case hrv                    = "hrv"
    case restingHR              = "resting_hr"
    case respiratoryRate        = "respiratory_rate"
    case sleep                  = "sleep"
    case oxygenSaturation       = "oxygen_saturation"
    case wristTemperature       = "wrist_temperature"

    // Activity
    case steps                  = "steps"
    case activeCalories         = "active_calories"
    case exerciseMinutes        = "exercise_minutes"
    case distanceWalkingRunning = "distance_walking_running"
    case timeInDaylight         = "time_in_daylight"

    // Fitness
    case vo2Max                 = "vo2_max"
    case cardioRecovery         = "cardio_recovery"
    case walkingHeartRate       = "walking_heart_rate"
    case walkingSpeed           = "walking_speed"
    case stairAscentSpeed       = "stair_ascent_speed"
    case stairDescentSpeed      = "stair_descent_speed"

    // Body
    case bodyMass               = "body_mass"

    // MARK: - Display

    var label: String {
        switch self {
        case .hrv:                    return "Heart Rate Variability (HRV)"
        case .restingHR:              return "Resting Heart Rate"
        case .respiratoryRate:        return "Respiratory Rate"
        case .sleep:                  return "Sleep Analysis"
        case .oxygenSaturation:       return "Blood Oxygen (SpO2)"
        case .wristTemperature:       return "Sleeping Wrist Temp"
        case .steps:                  return "Step Count"
        case .activeCalories:         return "Active Calories"
        case .exerciseMinutes:        return "Exercise Minutes"
        case .distanceWalkingRunning: return "Walking + Running Distance"
        case .timeInDaylight:         return "Time in Daylight"
        case .vo2Max:                 return "Cardio Fitness (VO2 Max)"
        case .cardioRecovery:         return "Cardio Recovery (1 min)"
        case .walkingHeartRate:       return "Walking Heart Rate"
        case .walkingSpeed:           return "Walking Speed"
        case .stairAscentSpeed:       return "Stair Ascent Speed"
        case .stairDescentSpeed:      return "Stair Descent Speed"
        case .bodyMass:               return "Body Mass"
        }
    }

    var description: String {
        switch self {
        case .hrv:                    return "Overnight SDNN — primary readiness signal"
        case .restingHR:              return "Morning resting pulse — tracks cardiovascular adaptation"
        case .respiratoryRate:        return "Breathing rate during sleep — illness and recovery marker"
        case .sleep:                  return "Hours and efficiency — cornerstone of recovery"
        case .oxygenSaturation:       return "Average SpO2 during sleep — requires Apple Watch"
        case .wristTemperature:       return "Deviation from baseline — illness detection. Watch Series 8+ / Ultra"
        case .steps:                  return "Yesterday's total step count"
        case .activeCalories:         return "Yesterday's active energy burned"
        case .exerciseMinutes:        return "Yesterday's exercise ring minutes"
        case .distanceWalkingRunning: return "Yesterday's total walking + running distance"
        case .timeInDaylight:         return "Yesterday's outdoor daylight exposure"
        case .vo2Max:                 return "Estimated aerobic capacity — requires Apple Watch + iPhone"
        case .cardioRecovery:         return "HR drop in first minute post-exercise — fitness marker. Apple Watch"
        case .walkingHeartRate:       return "7-day average HR during walks"
        case .walkingSpeed:           return "7-day average walking pace"
        case .stairAscentSpeed:       return "7-day average stair climb speed"
        case .stairDescentSpeed:      return "7-day average stair descent speed"
        case .bodyMass:               return "Most recent body weight reading"
        }
    }

    var icon: String {
        switch self {
        case .hrv:                    return "waveform.path.ecg"
        case .restingHR:              return "heart.fill"
        case .respiratoryRate:        return "lungs.fill"
        case .sleep:                  return "moon.zzz.fill"
        case .oxygenSaturation:       return "drop.fill"
        case .wristTemperature:       return "thermometer.medium"
        case .steps:                  return "figure.walk"
        case .activeCalories:         return "flame.fill"
        case .exerciseMinutes:        return "stopwatch.fill"
        case .distanceWalkingRunning: return "map.fill"
        case .timeInDaylight:         return "sun.max.fill"
        case .vo2Max:                 return "figure.run"
        case .cardioRecovery:         return "bolt.heart.fill"
        case .walkingHeartRate:       return "heart.circle"
        case .walkingSpeed:           return "speedometer"
        case .stairAscentSpeed:       return "arrow.up.right"
        case .stairDescentSpeed:      return "arrow.down.right"
        case .bodyMass:               return "scalemass.fill"
        }
    }

    var category: MetricCategory {
        switch self {
        case .hrv, .restingHR, .respiratoryRate, .sleep, .oxygenSaturation, .wristTemperature:
            return .recoverySleep
        case .steps, .activeCalories, .exerciseMinutes, .distanceWalkingRunning, .timeInDaylight:
            return .activity
        case .vo2Max, .cardioRecovery, .walkingHeartRate, .walkingSpeed, .stairAscentSpeed, .stairDescentSpeed:
            return .fitness
        case .bodyMass:
            return .body
        }
    }

    /// Metrics that are core to readiness — cannot be disabled
    var isCoreMetric: Bool {
        switch self {
        case .hrv, .restingHR, .sleep: return true
        default: return false
        }
    }
}

enum MetricCategory: String, CaseIterable {
    case recoverySleep = "Recovery & Sleep"
    case activity      = "Activity"
    case fitness       = "Fitness"
    case body          = "Body"

    var icon: String {
        switch self {
        case .recoverySleep: return "moon.zzz.fill"
        case .activity:      return "figure.walk"
        case .fitness:       return "figure.run"
        case .body:          return "scalemass.fill"
        }
    }
}

// MARK: - HealthMetricPreferences

/// Persists per-metric on/off toggles to UserDefaults.
/// Core metrics (HRV, resting HR, sleep) are always enabled and cannot be turned off.
final class HealthMetricPreferences: @unchecked Sendable {

    static let shared = HealthMetricPreferences()

    private let defaults = UserDefaults.standard
    private let keyPrefix = "health_metric_enabled_"

    private init() {}

    func isEnabled(_ metric: HealthMetric) -> Bool {
        if metric.isCoreMetric { return true }
        let key = keyPrefix + metric.rawValue
        // Default: enabled unless explicitly stored as false
        if defaults.object(forKey: key) == nil { return true }
        return defaults.bool(forKey: key)
    }

    func setEnabled(_ metric: HealthMetric, _ value: Bool) {
        guard !metric.isCoreMetric else { return }
        defaults.set(value, forKey: keyPrefix + metric.rawValue)
    }

    func enabledMetrics() -> Set<HealthMetric> {
        Set(HealthMetric.allCases.filter { isEnabled($0) })
    }

    func resetToDefaults() {
        for metric in HealthMetric.allCases where !metric.isCoreMetric {
            defaults.removeObject(forKey: keyPrefix + metric.rawValue)
        }
    }
}
