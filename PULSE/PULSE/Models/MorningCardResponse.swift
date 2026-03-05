import Foundation

struct MorningCardResponse: Codable {
    let readinessLevel: String          // "high" | "medium" | "low" | "alert"
    let headline: String
    let summary: String
    let workSuggestion: String
    let protocols: [ProtocolSuggestion]
    let avoidToday: [String]
    let oneFocus: String
    let goalNote: String

    enum CodingKeys: String, CodingKey {
        case readinessLevel = "readiness_level"
        case headline
        case summary
        case workSuggestion = "work_suggestion"
        case protocols
        case avoidToday = "avoid_today"
        case oneFocus = "one_focus"
        case goalNote = "goal_note"
    }
}

struct ProtocolSuggestion: Codable {
    let id: String
    let reason: String
}
