import Foundation

struct WellnessProtocol: Codable, Identifiable {
    let id: String
    let title: String
    let category: String
    let tags: [String]
    let triggerConditions: [String]
    let durationMinutes: Int
    let effort: Int                 // 0–5 (0 = none, 5 = high)
    let timing: String
    let protocolDescription: String
    let whyItWorks: String
    let source: String
    let phaseRelevance: [String]

    enum CodingKeys: String, CodingKey {
        case id, title, category, tags
        case triggerConditions = "trigger_conditions"
        case durationMinutes = "duration_minutes"
        case effort, timing
        case protocolDescription = "protocol"
        case whyItWorks = "why_it_works"
        case source
        case phaseRelevance = "phase_relevance"
    }
}
