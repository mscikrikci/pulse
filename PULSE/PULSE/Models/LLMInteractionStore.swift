import Foundation

/// App-wide shared instance. Initialized as empty at startup and replaced with the
/// disk-loaded version in PulseApp.task {}. AnthropicClient reads this at call time.
nonisolated(unsafe) var sharedLLMLogStore: LLMInteractionStore = .makeEmpty()

actor LLMInteractionStore {
    private var interactions: [LLMInteraction] = []
    private let fileURL: URL
    private let maxRetained = 200

    // MARK: - Init

    private init(interactions: [LLMInteraction], fileURL: URL) {
        self.interactions = interactions
        self.fileURL = fileURL
    }

    /// Returns an empty store with no backing file (used as a synchronous placeholder at init time).
    static func makeEmpty() -> LLMInteractionStore {
        LLMInteractionStore(interactions: [], fileURL: URL(fileURLWithPath: ""))
    }

    /// Loads persisted interactions from disk. Falls back to empty if file is missing or corrupt.
    static func load() async -> LLMInteractionStore {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return makeEmpty()
        }
        let url = docs.appendingPathComponent("llm_log.json")
        if FileManager.default.fileExists(atPath: url.path) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let raw = try? Data(contentsOf: url),
               let decoded = try? decoder.decode([LLMInteraction].self, from: raw) {
                return LLMInteractionStore(interactions: decoded, fileURL: url)
            }
        }
        return LLMInteractionStore(interactions: [], fileURL: url)
    }

    // MARK: - Write

    func record(_ interaction: LLMInteraction) {
        interactions.append(interaction)
        if interactions.count > maxRetained {
            interactions.removeFirst(interactions.count - maxRetained)
        }
        persist()
    }

    // MARK: - Read

    func recent(limit: Int = 50) -> [LLMInteraction] {
        Array(interactions.suffix(limit).reversed())
    }

    func forFeature(_ feature: LLMFeature) -> [LLMInteraction] {
        Array(interactions.filter { $0.feature == feature }.reversed())
    }

    func all() -> [LLMInteraction] {
        interactions.reversed()
    }

    // MARK: - Persistence

    private func persist() {
        guard !fileURL.path.isEmpty else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(interactions) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
