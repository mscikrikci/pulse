import Foundation

actor MemoryStore {

    private var episodic: [EpisodicMemory] = []
    private var patterns: [PatternMemory] = []
    private var identity: IdentitySummary?

    private let episodicURL: URL
    private let patternURL: URL
    private let identityURL: URL

    private let maxEpisodic = 60
    private let maxPatterns = 30

    // MARK: - Init

    private init(episodic: [EpisodicMemory], patterns: [PatternMemory], identity: IdentitySummary?,
                 episodicURL: URL, patternURL: URL, identityURL: URL) {
        self.episodic = episodic
        self.patterns = patterns
        self.identity = identity
        self.episodicURL = episodicURL
        self.patternURL = patternURL
        self.identityURL = identityURL
    }

    // MARK: - Load

    static func load() async -> MemoryStore {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            let fallback = URL(fileURLWithPath: "")
            return MemoryStore(episodic: [], patterns: [], identity: nil,
                               episodicURL: fallback, patternURL: fallback, identityURL: fallback)
        }

        let episodicURL = docs.appendingPathComponent("episodic_memory.json")
        let patternURL  = docs.appendingPathComponent("pattern_memory.json")
        let identityURL = docs.appendingPathComponent("identity_summary.json")

        let decoder = JSONDecoder()

        let episodic: [EpisodicMemory] = (try? decoder.decode(
            [String: [EpisodicMemory]].self,
            from: Data(contentsOf: episodicURL)
        ))?["entries"] ?? []

        let patterns: [PatternMemory] = (try? decoder.decode(
            [String: [PatternMemory]].self,
            from: Data(contentsOf: patternURL)
        ))?["patterns"] ?? []

        let identity: IdentitySummary? = try? decoder.decode(
            IdentitySummary.self,
            from: Data(contentsOf: identityURL)
        )

        return MemoryStore(episodic: episodic, patterns: patterns, identity: identity,
                           episodicURL: episodicURL, patternURL: patternURL, identityURL: identityURL)
    }

    // MARK: - Write

    func writeEpisodic(type: String, content: String, tags: [String], importance: String, source: String) -> String {
        let id = "mem_\(UUID().uuidString.prefix(8).lowercased())"
        let entry = EpisodicMemory(
            id: id,
            date: todayKey(),
            type: type,
            tags: tags,
            content: content,
            source: source,
            importance: importance
        )
        episodic.append(entry)
        saveEpisodic()
        return id
    }

    func writePattern(metric: String, patternType: String, description: String,
                      confidence: String, evidenceCount: Int, tags: [String]) -> String {
        let id = "pat_\(UUID().uuidString.prefix(8).lowercased())"
        let pattern = PatternMemory(
            id: id,
            metric: metric,
            patternType: patternType,
            description: description,
            confidence: confidence,
            evidenceCount: evidenceCount,
            lastObserved: todayKey(),
            tags: tags
        )
        patterns.append(pattern)
        savePatterns()
        return id
    }

    func writeIdentitySummary(summary: String, keySensitivities: [String],
                               keyStrengths: [String], activeFocus: String) {
        identity = IdentitySummary(
            lastUpdated: todayKey(),
            generatedBy: "weekly_review",
            summary: summary,
            keySensitivities: keySensitivities,
            keyStrengths: keyStrengths,
            activeFocus: activeFocus
        )
        saveIdentity()
    }

    // MARK: - Read Accessors (debug / UI use)

    var allEpisodic: [EpisodicMemory] { episodic }
    var allPatterns: [PatternMemory] { patterns }
    var currentIdentity: IdentitySummary? { identity }

    // MARK: - Read / Assemble

    /// Assemble the memory context to inject into the agent frame.
    /// - `relevantTags`: condition flags or event tags from the current session.
    func buildMemoryContext(relevantTags: Set<String> = []) -> MemoryContext {
        // Episodic: last 5 high-importance + last 3 any (deduped, newest-first order)
        let highImp = episodic.filter { $0.importance == "high" }.suffix(5)
        let recent  = episodic.suffix(3)
        var seenIds = Set<String>()
        var selectedEpisodic: [EpisodicMemory] = []
        for e in (Array(highImp) + Array(recent)).reversed() {
            if seenIds.insert(e.id).inserted {
                selectedEpisodic.insert(e, at: 0)
            }
        }

        // Patterns: all high-confidence + medium-confidence matching relevantTags
        let selectedPatterns: [PatternMemory]
        if relevantTags.isEmpty {
            selectedPatterns = patterns.filter { $0.confidence == "high" }
        } else {
            selectedPatterns = patterns.filter { p in
                p.confidence == "high" ||
                (p.confidence == "medium" && !Set(p.tags).isDisjoint(with: relevantTags))
            }
        }

        return MemoryContext(
            identitySummary: identity?.summary,
            recentEpisodic: selectedEpisodic,
            patterns: selectedPatterns
        )
    }

    // MARK: - Prune

    /// Prune stores to their size limits. Call once per app open.
    func pruneIfNeeded() {
        var episodicChanged = false
        while episodic.count > maxEpisodic {
            // Remove oldest low-importance entry first; if none, remove oldest overall
            if let idx = episodic.firstIndex(where: { $0.importance == "low" }) {
                episodic.remove(at: idx)
            } else {
                episodic.removeFirst()
            }
            episodicChanged = true
        }
        if episodicChanged { saveEpisodic() }

        var patternChanged = false
        while patterns.count > maxPatterns {
            // Remove lowest-confidence entry first; if tie, remove oldest by lastObserved
            if let idx = patterns.firstIndex(where: { $0.confidence == "low" }) {
                patterns.remove(at: idx)
            } else if let idx = patterns.min(by: { $0.lastObserved < $1.lastObserved }).flatMap({ p in patterns.firstIndex(where: { $0.id == p.id }) }) {
                patterns.remove(at: idx)
            }
            patternChanged = true
        }
        if patternChanged { savePatterns() }
    }

    // MARK: - Persistence

    private func saveEpisodic() {
        guard !episodicURL.path.isEmpty else { return }
        let wrapper = ["entries": episodic]
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: episodicURL, options: .atomic)
        }
    }

    private func savePatterns() {
        guard !patternURL.path.isEmpty else { return }
        let wrapper = ["patterns": patterns]
        if let data = try? JSONEncoder().encode(wrapper) {
            try? data.write(to: patternURL, options: .atomic)
        }
    }

    private func saveIdentity() {
        guard !identityURL.path.isEmpty, let identity else { return }
        if let data = try? JSONEncoder().encode(identity) {
            try? data.write(to: identityURL, options: .atomic)
        }
    }

    // MARK: - Helpers

    private func todayKey() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
}
