import Foundation

struct ProtocolMatcher {
    private let protocols: [WellnessProtocol]

    // MARK: - Init

    init() {
        guard let url = Bundle.main.url(forResource: "protocols", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([WellnessProtocol].self, from: data) else {
            print("[ProtocolMatcher] Failed to load protocols.json")
            self.protocols = []
            return
        }
        self.protocols = decoded
    }

    // MARK: - Public

    /// Evaluates condition flags from a HealthSummary + baselines + user-reported events,
    /// then returns top 4–5 matched protocols.
    func match(
        summary: HealthSummary,
        baselines: Baselines,
        readinessLevel: String,
        userEvents: [String] = []
    ) -> [WellnessProtocol] {
        let flags = evaluateFlags(summary: summary, baselines: baselines, userEvents: userEvents)
        return selectProtocols(flags: flags, readinessLevel: readinessLevel)
    }

    /// Returns condition flags for a given summary + baselines + user-reported events.
    func evaluateFlags(
        summary: HealthSummary,
        baselines: Baselines,
        userEvents: [String] = []
    ) -> Set<String> {
        var flags = Set<String>()

        // HRV flags
        if let hrv = summary.hrv, let avg7 = baselines.hrv7DayAvg, avg7 > 0 {
            let pct = (hrv - avg7) / avg7
            if pct < -0.25 { flags.insert("very_low_hrv") }
            else if pct < -0.15 { flags.insert("low_hrv") }
        }

        // Resting HR flags
        if let rhr = summary.restingHR, let avg30 = baselines.restingHR30DayAvg {
            if rhr > avg30 + 5 { flags.insert("elevated_rhr") }
        }

        // Sleep flags
        if let hours = summary.sleepHours, let eff = summary.sleepEfficiency {
            if hours < 6.5 || eff < 0.75 { flags.insert("poor_sleep") }
        } else if summary.sleepHours == nil {
            flags.insert("poor_sleep")
        }

        // Respiratory rate flags
        if let resp = summary.respiratoryRate {
            if resp > 17 { flags.insert("elevated_respiratory_rate") }
        }

        // User-reported subjective events mapped to protocol trigger flags
        for event in userEvents {
            switch event {
            case "high_stress", "sadness", "argument", "anger":
                flags.insert("high_stress")
            case "fatigue":
                flags.insert("poor_sleep")      // fatigue → recovery/sleep protocols
            case "health_issue":
                flags.insert("possible_illness")
            default:
                break
            }
        }

        // Combined flags derived from multiple signals
        if flags.contains("low_hrv") || flags.contains("very_low_hrv"),
           flags.contains("elevated_rhr") {
            flags.insert("high_stress")
        }
        if flags.contains("elevated_respiratory_rate"),
           flags.contains("elevated_rhr") {
            flags.insert("possible_illness")
        }

        // Peak readiness: HRV above baseline + good sleep
        if let hrv = summary.hrv, let avg7 = baselines.hrv7DayAvg, avg7 > 0 {
            let pct = (hrv - avg7) / avg7
            if pct > 0.10, let sleepHours = summary.sleepHours, sleepHours >= 7 {
                flags.insert("peak_readiness")
            }
        }

        // Well-recovered: no negative flags present (regardless of HRV availability)
        let negativeFlags: Set<String> = [
            "low_hrv", "very_low_hrv", "elevated_rhr", "poor_sleep",
            "elevated_respiratory_rate", "high_stress", "possible_illness"
        ]
        if flags.isDisjoint(with: negativeFlags) {
            flags.insert("well_recovered")
        }

        return flags
    }

    /// Accepts precomputed condition flags (skips health data evaluation).
    /// Used by the ToolExecutor `get_protocols` tool so the LLM can specify flags directly.
    func matchByFlags(flags: Set<String>, maxEffort: String? = nil) -> [WellnessProtocol] {
        var matched = protocols.filter { proto in
            proto.triggerConditions.contains(where: { flags.contains($0) })
        }
        if let maxEffortStr = maxEffort {
            let effortMap = ["none": 0, "low": 1, "medium": 2, "high": 3, "very_high": 4]
            let maxVal = effortMap[maxEffortStr] ?? 5
            matched = matched.filter { $0.effort <= maxVal }
        }
        return Array(matched.prefix(5))
    }

    // MARK: - Private

    private func selectProtocols(flags: Set<String>, readinessLevel: String) -> [WellnessProtocol] {
        let matched = protocols.filter { proto in
            proto.triggerConditions.contains(where: { flags.contains($0) })
        }

        // On low/alert readiness days sort by lowest effort first
        let sorted: [WellnessProtocol]
        if readinessLevel == "low" || readinessLevel == "alert" {
            sorted = matched.sorted { $0.effort < $1.effort }
        } else {
            sorted = matched.sorted { $0.effort > $1.effort }
        }

        return Array(sorted.prefix(5))
    }
}
