import Foundation

actor TrainerStore {
    private var data: TrainerStoreData
    private let fileURL: URL

    // MARK: - Init

    private init(data: TrainerStoreData, fileURL: URL) {
        self.data = data
        self.fileURL = fileURL
    }

    static func load() async throws -> TrainerStore {
        let url = try storeURL()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let raw = try Data(contentsOf: url)
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                let storeData = try decoder.decode(TrainerStoreData.self, from: raw)
                return TrainerStore(data: storeData, fileURL: url)
            } catch {
                print("[TrainerStore] Load failed, starting fresh: \(error)")
                return TrainerStore(data: .empty(), fileURL: url)
            }
        } else {
            return TrainerStore(data: .empty(), fileURL: url)
        }
    }

    // MARK: - Profile

    var profile: TrainerProfile? { data.profile }

    func saveProfile(_ profile: TrainerProfile) throws {
        data.profile = profile
        try save()
    }

    // MARK: - Plan

    var currentPlan: WeeklyPlan? { data.currentPlan }
    var planHistory: [WeeklyPlan] { data.planHistory }

    func savePlan(_ plan: WeeklyPlan) throws {
        // Archive current plan to history before replacing
        if let existing = data.currentPlan {
            data.planHistory.append(existing)
            // Keep last 4 weeks
            if data.planHistory.count > 4 {
                data.planHistory = Array(data.planHistory.suffix(4))
            }
        }
        data.currentPlan = plan
        try save()
    }

    // MARK: - Workout Logs

    var workoutLogs: [WorkoutLog] { data.workoutLogs }

    /// Returns the most recent N logs, sorted newest first.
    func recentLogs(limit: Int = 20) -> [WorkoutLog] {
        data.workoutLogs
            .sorted { $0.completedAt > $1.completedAt }
            .prefix(limit)
            .map { $0 }
    }

    func saveUploadedProgram(text: String, name: String) throws {
        data.uploadedProgram = text
        data.uploadedProgramName = name
        try save()
    }

    func clearUploadedProgram() throws {
        data.uploadedProgram = nil
        data.uploadedProgramName = nil
        try save()
    }

    var uploadedProgram: String? { data.uploadedProgram }
    var uploadedProgramName: String? { data.uploadedProgramName }

    func logWorkout(_ log: WorkoutLog) throws {
        data.workoutLogs.append(log)
        // Keep only last 90 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -90, to: Date()) ?? Date()
        data.workoutLogs = data.workoutLogs.filter { $0.completedAt >= cutoff }
        try save()
    }

    /// Returns the log for a specific workout id if it was completed today.
    func todayLog(for workoutId: String) -> WorkoutLog? {
        let todayKey = dateKey(from: Date())
        return data.workoutLogs.first { $0.workoutId == workoutId && $0.date == todayKey }
    }

    // MARK: - Private

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
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
        return docs.appendingPathComponent("trainer_store.json")
    }

    private func dateKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}
