import Foundation

struct DailyTask: Identifiable, Codable {
    var id: UUID = UUID()
    let source: String       // "morning_card" | "check_in"
    let title: String        // Human-readable action text
    let protocolId: String?  // Linked protocol id, if applicable
    var isCompleted: Bool = false
    let createdAt: Date
}
