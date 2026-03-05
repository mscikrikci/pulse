import SwiftUI

struct MemoryDebugView: View {

    enum Section: String, CaseIterable {
        case context  = "Context"
        case identity = "Identity"
        case episodic = "Episodic"
        case patterns = "Patterns"
    }

    @State private var selectedSection: Section = .context
    @State private var identity: IdentitySummary? = nil
    @State private var episodic: [EpisodicMemory] = []
    @State private var patterns: [PatternMemory] = []
    @State private var showClearConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Picker("Section", selection: $selectedSection) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            Divider()

            ScrollView {
                switch selectedSection {
                case .context:   contextView
                case .identity:  identityView
                case .episodic:  episodicView
                case .patterns:  patternsView
                }
            }
        }
        .navigationTitle("Memory Debug")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
            ToolbarItem(placement: .destructiveAction) {
                Button("Clear All", role: .destructive) { showClearConfirm = true }
                    .foregroundStyle(.red)
            }
        }
        .confirmationDialog("Clear all long-term memory?", isPresented: $showClearConfirm, titleVisibility: .visible) {
            Button("Clear Memory", role: .destructive) { clearAllMemory() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This deletes episodic memory, patterns, and the identity summary. It cannot be undone.")
        }
        .task { await loadMemory() }
    }

    // MARK: - Context Preview

    private var contextView: some View {
        VStack(alignment: .leading, spacing: 12) {
            infoRow("Episodic entries", "\(episodic.count)")
            infoRow("Pattern entries", "\(patterns.count)")
            infoRow("Identity summary", identity == nil ? "None" : "Present")

            Divider()

            Text("Agent Frame Injection Preview")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Text(buildContextPreview())
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .padding()
    }

    // MARK: - Identity

    private var identityView: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let id = identity {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Updated \(id.lastUpdated)", systemImage: "clock")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(id.summary)
                        .font(.subheadline)

                    if !id.activeFocus.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Active Focus").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(id.activeFocus).font(.callout)
                        }
                    }

                    if !id.keySensitivities.isEmpty {
                        tagGroup(label: "Sensitivities", items: id.keySensitivities, color: .orange)
                    }

                    if !id.keyStrengths.isEmpty {
                        tagGroup(label: "Strengths", items: id.keyStrengths, color: .green)
                    }
                }
            } else {
                ContentUnavailableView(
                    "No Identity Summary",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("The identity summary is written by the weekly review agent after it runs.")
                )
            }
        }
        .padding()
    }

    // MARK: - Episodic

    private var episodicView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if episodic.isEmpty {
                ContentUnavailableView(
                    "No Episodic Memories",
                    systemImage: "brain",
                    description: Text("The agent writes episodic memories when it observes noteworthy events.")
                )
                .padding(.top, 40)
            } else {
                ForEach(episodic.reversed()) { entry in
                    episodicRow(entry)
                    Divider().padding(.leading)
                }
            }
        }
    }

    private func episodicRow(_ e: EpisodicMemory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(e.date)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                importanceBadge(e.importance)
                Text(e.type.replacingOccurrences(of: "_", with: " "))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(e.source)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Text(e.content)
                .font(.subheadline)
            if !e.tags.isEmpty {
                Text(e.tags.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.blue)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Patterns

    private var patternsView: some View {
        VStack(alignment: .leading, spacing: 0) {
            if patterns.isEmpty {
                ContentUnavailableView(
                    "No Patterns",
                    systemImage: "waveform.path",
                    description: Text("The agent writes patterns when it identifies correlations or behavioral drivers.")
                )
                .padding(.top, 40)
            } else {
                ForEach(patterns) { p in
                    patternRow(p)
                    Divider().padding(.leading)
                }
            }
        }
    }

    private func patternRow(_ p: PatternMemory) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(p.metric)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                confidenceBadge(p.confidence)
                Spacer()
                Text("×\(p.evidenceCount)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(p.description)
                .font(.subheadline)
            Text("Last observed: \(p.lastObserved)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    private func tagGroup(label: String, items: [String], color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            FlowLayout(spacing: 6) {
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.caption)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(color.opacity(0.12))
                        .foregroundStyle(color)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func importanceBadge(_ importance: String) -> some View {
        let color: Color = importance == "high" ? .red : importance == "medium" ? .orange : .secondary
        return Text(importance)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func confidenceBadge(_ confidence: String) -> some View {
        let color: Color = confidence == "high" ? .green : confidence == "medium" ? .orange : .secondary
        return Text(confidence)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    // MARK: - Context Preview Builder

    /// Recreates what buildMemoryContext() would inject into the agent frame.
    private func buildContextPreview() -> String {
        // Selection logic mirrors MemoryStore.buildMemoryContext()
        let highImp = episodic.filter { $0.importance == "high" }.suffix(5)
        let recent  = episodic.suffix(3)
        var seenIds = Set<String>()
        var selected: [EpisodicMemory] = []
        for e in (Array(highImp) + Array(recent)).reversed() {
            if seenIds.insert(e.id).inserted { selected.insert(e, at: 0) }
        }
        let selectedPatterns = patterns.filter { $0.confidence == "high" }

        if identity == nil && selected.isEmpty && selectedPatterns.isEmpty {
            return "(no memory will be injected into the next agent call)"
        }

        var lines: [String] = []
        if let id = identity {
            lines.append("=== WHAT I KNOW ABOUT YOU ===")
            lines.append(id.summary)
        }
        if !selected.isEmpty {
            lines.append("")
            lines.append("=== RECENT NOTABLE EVENTS ===")
            for e in selected { lines.append("- [\(e.date)] \(e.content)") }
        }
        if !selectedPatterns.isEmpty {
            lines.append("")
            lines.append("=== YOUR PATTERNS ===")
            for p in selectedPatterns { lines.append("- \(p.description)") }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Load / Clear

    private func loadMemory() async {
        let store = await MemoryStore.load()
        self.identity  = await store.currentIdentity
        self.episodic  = await store.allEpisodic
        self.patterns  = await store.allPatterns
    }

    private func clearAllMemory() {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        for name in ["episodic_memory.json", "pattern_memory.json", "identity_summary.json"] {
            try? FileManager.default.removeItem(at: docs.appendingPathComponent(name))
        }
        identity = nil
        episodic = []
        patterns = []
    }
}
