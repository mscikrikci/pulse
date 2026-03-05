import Foundation

/// Persists the weekly review to disk, keyed by ISO week (e.g. "2026-W10").
/// A review generated for a given week is always returned when that week is current.
struct WeeklyReviewStore {

    private struct PersistedReview: Codable {
        let weekKey: String         // e.g. "2026-W10"
        let generatedAt: Date
        let review: WeeklyReviewResponse
    }

    static func save(_ review: WeeklyReviewResponse) {
        guard let url = storeURL() else { return }
        let persisted = PersistedReview(weekKey: currentWeekKey(), generatedAt: Date(), review: review)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns the cached review if it was generated for the current ISO week, otherwise nil.
    static func loadIfCurrentWeek() -> (review: WeeklyReviewResponse, generatedAt: Date)? {
        guard let url = storeURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let persisted = try? JSONDecoder().decode(PersistedReview.self, from: data),
              persisted.weekKey == currentWeekKey() else { return nil }
        return (persisted.review, persisted.generatedAt)
    }

    static func currentWeekKey() -> String {
        var cal = Calendar(identifier: .iso8601)
        cal.timeZone = .current
        let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: Date())
        let year = comps.yearForWeekOfYear ?? Calendar.current.component(.year, from: Date())
        let week = comps.weekOfYear ?? 1
        return String(format: "%04d-W%02d", year, week)
    }

    private static func storeURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent("weekly_review_cache.json")
    }
}
