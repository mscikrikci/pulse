import Foundation

// MARK: - Episodic Memory

/// A notable event, observation, or user statement stored for future recall.
struct EpisodicMemory: Identifiable, Codable {
    let id: String          // e.g. "mem_a1b2c3d4"
    let date: String        // "yyyy-MM-dd"
    let type: String        // "observation" | "pattern" | "milestone" | "user_statement" | "anomaly"
    let tags: [String]      // e.g. ["hrv", "stress", "work"]
    let content: String     // 1–3 sentence narrative
    let source: String      // "morning_card" | "chat" | "weekly_review"
    let importance: String  // "low" | "medium" | "high"
}

// MARK: - Pattern Memory

/// A learned correlation or behavioral tendency observed across multiple sessions.
struct PatternMemory: Identifiable, Codable {
    let id: String              // e.g. "pat_a1b2c3d4"
    let metric: String          // primary metric: "hrv", "sleep_hours", etc.
    let patternType: String     // "correlation" | "positive_driver" | "negative_driver"
    let description: String     // 1–2 sentence description of the pattern
    let confidence: String      // "low" | "medium" | "high"
    let evidenceCount: Int      // number of observed incidents
    let lastObserved: String    // "yyyy-MM-dd"
    let tags: [String]

    enum CodingKeys: String, CodingKey {
        case id, metric
        case patternType    = "pattern_type"
        case description, confidence
        case evidenceCount  = "evidence_count"
        case lastObserved   = "last_observed"
        case tags
    }
}

// MARK: - Identity Summary

/// Compressed third-person model of the user, rewritten weekly by the weekly review agent.
struct IdentitySummary: Codable {
    let lastUpdated: String         // "yyyy-MM-dd"
    let generatedBy: String         // "weekly_review"
    let summary: String             // 3–5 sentence compressed user model
    let keySensitivities: [String]  // e.g. ["alcohol → HRV", "work_stress → HRV"]
    let keyStrengths: [String]      // e.g. ["sleep_consistency", "morning_routine"]
    let activeFocus: String         // e.g. "Phase 2 (Build) — Zone 2 cardio 2-3x/week"

    enum CodingKeys: String, CodingKey {
        case lastUpdated        = "last_updated"
        case generatedBy        = "generated_by"
        case summary
        case keySensitivities   = "key_sensitivities"
        case keyStrengths       = "key_strengths"
        case activeFocus        = "active_focus"
    }
}

// MARK: - Memory Context (assembled before each agent run)

/// Assembled from MemoryStore before each agentic run and injected into the agent frame.
struct MemoryContext {
    let identitySummary: String?
    let recentEpisodic: [EpisodicMemory]
    let patterns: [PatternMemory]

    var isEmpty: Bool {
        identitySummary == nil && recentEpisodic.isEmpty && patterns.isEmpty
    }

    static let empty = MemoryContext(identitySummary: nil, recentEpisodic: [], patterns: [])
}
