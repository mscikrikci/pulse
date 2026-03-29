import Foundation

struct UserProfile: Codable {
    var age: Int?
    var gender: String?          // "male" | "female" | "other" | "prefer_not_to_say"
    var heightCm: Double?
    var weightKg: Double?
    var conditions: [String]     // mix of predefined IDs and custom free-text strings

    static let empty = UserProfile(age: nil, gender: nil, heightCm: nil, weightKg: nil, conditions: [])

    static let predefinedConditions: [(id: String, label: String)] = [
        ("hypertension",   "Hypertension"),
        ("heart_disease",  "Heart disease"),
        ("diabetes_t2",    "Type 2 diabetes"),
        ("asthma",         "Asthma"),
        ("knee_joint",     "Knee / joint problems"),
        ("back_spine",     "Back / spine issues"),
        ("anxiety",        "Anxiety / stress disorder"),
        ("sleep_apnea",    "Sleep apnea"),
        ("thyroid",        "Thyroid condition"),
        ("arthritis",      "Arthritis"),
    ]

    // MARK: - Formatted strings for context injection

    var heightDisplay: String? {
        guard let cm = heightCm else { return nil }
        let totalInches = cm / 2.54
        let feet = Int(totalInches / 12)
        let inches = Int(totalInches.truncatingRemainder(dividingBy: 12).rounded())
        return "\(Int(cm.rounded())) cm (\(feet)'\(inches)\")"
    }

    var weightDisplay: String? {
        guard let kg = weightKg else { return nil }
        let lbs = Int((kg * 2.20462).rounded())
        return "\(Int(kg.rounded())) kg (\(lbs) lbs)"
    }

    var conditionLabels: [String] {
        conditions.map { id in
            Self.predefinedConditions.first { $0.id == id }?.label ?? id
        }
    }

    var isEmpty: Bool {
        age == nil && gender == nil && heightCm == nil && weightKg == nil && conditions.isEmpty
    }
}

