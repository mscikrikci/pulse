import Foundation

/// Persists today's morning card to disk so it survives app restarts.
struct MorningCardStore {

    private struct PersistedCard: Codable {
        let date: String            // "yyyy-MM-dd"
        let card: MorningCardResponse
    }

    static func save(_ card: MorningCardResponse) {
        guard let url = try? storeURL() else { return }
        let persisted = PersistedCard(date: todayKey(), card: card)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: url, options: .atomic)
    }

    /// Returns today's card if it was generated today, otherwise nil.
    static func loadIfToday() -> MorningCardResponse? {
        guard let url = try? storeURL(),
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let persisted = try? JSONDecoder().decode(PersistedCard.self, from: data),
              persisted.date == todayKey() else { return nil }
        return persisted.card
    }

    private static func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }

    private static func storeURL() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppError.storeLoadFailed("Documents directory not found")
        }
        return docs.appendingPathComponent("morning_card.json")
    }
}
