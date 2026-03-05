import Foundation

struct ConflictWarning: Identifiable {
    let id = UUID()
    let title: String
    let message: String
}

struct GoalConflictDetector {

    static func detect(
        goals: [GoalDefinition],
        activityAlerts: [ActivityAlert]
    ) -> [ConflictWarning] {
        var warnings: [ConflictWarning] = []

        let hasHRVGoal = goals.contains { $0.metric == .hrv && $0.mode == .target }
        let caloriesAlert = activityAlerts.first { $0.metric == "active_calories" }

        // High calorie target + HRV improvement goal
        if hasHRVGoal, let cal = caloriesAlert, cal.dailyTarget > 800 {
            warnings.append(ConflictWarning(
                title: "High Activity Target + HRV Goal",
                message: "A daily calorie target above 800 kcal requires strong recovery. Start lower and adjust based on your HRV trend over the first 2 weeks."
            ))
        }

        // Aggressive RHR target in short timeframe
        if let rhrGoal = goals.first(where: { $0.metric == .restingHR && $0.mode == .target }),
           let weeks = rhrGoal.timeframeWeeks {
            let reduction = rhrGoal.baselineAtSet - rhrGoal.targetValue
            if reduction > 10 && weeks < 8 {
                warnings.append(ConflictWarning(
                    title: "Aggressive RHR Timeframe",
                    message: "Resting HR adaptations typically take 8–16 weeks. A \(String(format: "%.0f", reduction))bpm reduction in \(weeks) weeks may set unrealistic expectations."
                ))
            }
        }

        return warnings
    }
}
