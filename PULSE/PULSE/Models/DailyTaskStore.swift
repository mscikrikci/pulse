import Foundation

/// Persists today's task list to disk so it survives app restarts.
/// Automatically discards data from previous days.
struct DailyTaskStore {

    private struct PersistedTasks: Codable {
        let date: String
        var tasks: [DailyTask]
    }

    static func save(_ tasks: [DailyTask]) {
        guard let url = storeURL() else { return }
        let persisted = PersistedTasks(date: todayKey(), tasks: tasks)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns today's task list. On a new day, daily tasks are discarded but habit tasks
    /// are carried over with completion state reset to false. Returns nil if no file exists.
    static func loadIfToday() -> [DailyTask]? {
        guard let url = storeURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let persisted = try? JSONDecoder().decode(PersistedTasks.self, from: data) else { return nil }
        if persisted.date == todayKey() {
            return persisted.tasks
        } else {
            // New day: carry over habit tasks with completion state reset
            let habits = persisted.tasks.filter(\.isHabit).map { task -> DailyTask in
                var t = task
                t.isCompleted = false
                return t
            }
            return habits.isEmpty ? nil : habits
        }
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func storeURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("daily_tasks.json")
    }
}
