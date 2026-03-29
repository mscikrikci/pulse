import Foundation

struct DailyTask: Identifiable, Codable {
    var id: UUID = UUID()
    let source: String       // "morning_card" | "check_in" | "chat"
    let title: String        // Human-readable action text
    let protocolId: String?  // Linked protocol id, if applicable
    var isCompleted: Bool = false
    var isHabit: Bool = false  // Habit tasks persist across days; daily tasks reset each day
    let createdAt: Date
}
