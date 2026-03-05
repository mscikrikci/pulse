import Foundation

actor TrendStore {
    private var data: TrendStoreData
    private let fileURL: URL

    // MARK: - Init

    private init(data: TrendStoreData, fileURL: URL) {
        self.data = data
        self.fileURL = fileURL
    }

    static func load() async throws -> TrendStore {
        let url = try Self.storeURL()
        let emptyData = TrendStoreData(lastUpdated: Date(), baselines: Baselines(), history: [], baselineDataDays: 0)
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let raw = try Data(contentsOf: url)
                let storeData = try JSONDecoder().decode(TrendStoreData.self, from: raw)
                return TrendStore(data: storeData, fileURL: url)
            } catch {
                print("[TrendStore] Load failed, starting fresh: \(error)")
                return TrendStore(data: emptyData, fileURL: url)
            }
        } else {
            return TrendStore(data: emptyData, fileURL: url)
        }
    }

    // MARK: - Public API

    var baselineStatus: BaselineStatus {
        switch data.baselineDataDays {
        case 0..<7:  return .cold
        case 7..<30: return .building
        default:     return .established
        }
    }

    var baselines: Baselines {
        data.baselines
    }

    var history: [DayEntry] {
        data.history
    }

    var storeData: TrendStoreData {
        data
    }

    /// Merges a new HealthSummary into the history and recomputes baselines.
    func update(with summary: HealthSummary) async throws {
        let key = Self.dateKey(from: summary.date)

        // Upsert today's entry
        // Preserve existing alcohol/events fields when upserting today's entry
        let existing = data.history.first(where: { $0.date == key })
        let entry = DayEntry(
            date: key,
            hrv: summary.hrv,
            restingHR: summary.restingHR,
            sleepHours: summary.sleepHours,
            sleepEfficiency: summary.sleepEfficiency,
            respiratoryRate: summary.respiratoryRate,
            activeCalories: summary.activeCalories,
            steps: summary.steps,
            alcoholReported: existing?.alcoholReported,
            events: existing?.events,
            vo2Max: summary.vo2Max,
            cardioRecovery: summary.cardioRecovery,
            walkingHeartRate: summary.walkingHeartRate,
            walkingSpeed: summary.walkingSpeed,
            stairAscentSpeed: summary.stairAscentSpeed,
            stairDescentSpeed: summary.stairDescentSpeed
        )

        if let idx = data.history.firstIndex(where: { $0.date == key }) {
            data.history[idx] = entry
        } else {
            data.history.append(entry)
        }

        // Keep only last 30 days
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        data.history = data.history.filter {
            guard let d = Self.date(from: $0.date) else { return false }
            return d >= cutoff
        }

        data.baselineDataDays = data.history.count
        data.lastUpdated = Date()
        data.baselines = computeBaselines()

        try save()
    }

    func recordAlcohol(_ reported: Bool, for date: Date) async throws {
        let key = Self.dateKey(from: date)
        if let idx = data.history.firstIndex(where: { $0.date == key }) {
            data.history[idx].alcoholReported = reported
            try save()
        }
    }

    func recordEvents(_ events: [String], for date: Date) async throws {
        let key = Self.dateKey(from: date)
        if let idx = data.history.firstIndex(where: { $0.date == key }) {
            data.history[idx].events = events
            try save()
        }
    }

    // MARK: - Private

    private func save() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.storeSaveFailed(error.localizedDescription)
        }
    }

    private func computeBaselines() -> Baselines {
        let all = data.history
        let last7 = Array(all.suffix(7))
        let last30 = all

        return Baselines(
            hrv7DayAvg: avg(last7.compactMap(\.hrv)),
            hrv30DayAvg: avg(last30.compactMap(\.hrv)),
            restingHR7DayAvg: avg(last7.compactMap(\.restingHR)),
            restingHR30DayAvg: avg(last30.compactMap(\.restingHR)),
            sleepHours7DayAvg: avg(last7.compactMap(\.sleepHours)),
            sleepHours30DayAvg: avg(last30.compactMap(\.sleepHours)),
            sleepEfficiency30DayAvg: avg(last30.compactMap(\.sleepEfficiency)),
            respiratoryRate30DayAvg: avg(last30.compactMap(\.respiratoryRate)),
            activeCalories7DayAvg: avg(last7.compactMap(\.activeCalories)),
            steps7DayAvg: avg(last7.compactMap { $0.steps.map(Double.init) }),
            vo2Max30DayAvg: avg(last30.compactMap(\.vo2Max)),
            vo2Max7DayAvg: avg(last7.compactMap(\.vo2Max)),
            walkingSpeed30DayAvg: avg(last30.compactMap(\.walkingSpeed)),
            walkingSpeed7DayAvg: avg(last7.compactMap(\.walkingSpeed)),
            walkingHeartRate30DayAvg: avg(last30.compactMap(\.walkingHeartRate))
        )
    }

    private func avg(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    private static func storeURL() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppError.storeLoadFailed("Documents directory not found")
        }
        return docs.appendingPathComponent("trend_store.json")
    }

    private static func dateKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }

    private static func date(from key: String) -> Date? {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: key)
    }
}
