import Foundation

actor GoalStore {
    private var data: GoalStoreData
    private let fileURL: URL

    private init(data: GoalStoreData, fileURL: URL) {
        self.data = data
        self.fileURL = fileURL
    }

    static func load() async throws -> GoalStore {
        let url = try storeURL()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let raw = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(GoalStoreData.self, from: raw)
                return GoalStore(data: decoded, fileURL: url)
            } catch {
                print("[GoalStore] Load failed, starting fresh: \(error)")
                return GoalStore(data: .empty(), fileURL: url)
            }
        }
        return GoalStore(data: .empty(), fileURL: url)
    }

    // MARK: - Public API

    var goals: [GoalDefinition] { data.outcomeGoals }
    var activityAlerts: [ActivityAlert] { data.activityAlerts }
    var storeData: GoalStoreData { data }

    func save(goal: GoalDefinition) throws {
        if let idx = data.outcomeGoals.firstIndex(where: { $0.id == goal.id }) {
            data.outcomeGoals[idx] = goal
        } else {
            data.outcomeGoals.append(goal)
        }
        try persist()
    }

    func delete(goalId: String) throws {
        data.outcomeGoals.removeAll { $0.id == goalId }
        try persist()
    }

    func save(activityAlert: ActivityAlert) throws {
        if let idx = data.activityAlerts.firstIndex(where: { $0.metric == activityAlert.metric }) {
            data.activityAlerts[idx] = activityAlert
        } else {
            data.activityAlerts.append(activityAlert)
        }
        try persist()
    }

    func advancePhase(goalId: String) throws {
        guard let idx = data.outcomeGoals.firstIndex(where: { $0.id == goalId }) else { return }
        let current = data.outcomeGoals[idx].currentPhase ?? 1
        data.outcomeGoals[idx].currentPhase = current + 1
        data.outcomeGoals[idx].phaseStartDate = dateKey(from: Date())
        try persist()
    }

    // MARK: - Private

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.storeSaveFailed(error.localizedDescription)
        }
    }

    private static func storeURL() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppError.storeLoadFailed("Documents directory not found")
        }
        return docs.appendingPathComponent("goal_store.json")
    }

    private func dateKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
