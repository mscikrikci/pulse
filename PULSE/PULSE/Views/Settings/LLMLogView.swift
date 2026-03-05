import SwiftUI

// MARK: - Log List View

struct LLMLogView: View {
    let logStore: LLMInteractionStore

    @State private var interactions: [LLMInteraction] = []
    @State private var selectedFeature: LLMFeature? = nil
    @State private var selectedInteraction: LLMInteraction? = nil

    private var filtered: [LLMInteraction] {
        guard let f = selectedFeature else { return interactions }
        return interactions.filter { $0.feature == f }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Feature filter chips
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    filterChip(nil, label: "All")
                    ForEach(LLMFeature.allCases, id: \.self) { feature in
                        filterChip(feature, label: feature.rawValue)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
            }
            Divider()

            if interactions.isEmpty {
                ContentUnavailableView(
                    "No LLM Calls Yet",
                    systemImage: "cpu",
                    description: Text("Generate a morning card or send a chat message to see logs here.")
                )
            } else if filtered.isEmpty {
                ContentUnavailableView(
                    "No \(selectedFeature?.rawValue ?? "") Calls",
                    systemImage: "line.3.horizontal.decrease.circle"
                )
            } else {
                List(filtered) { interaction in
                    Button {
                        selectedInteraction = interaction
                    } label: {
                        LLMLogRowView(interaction: interaction)
                    }
                    .buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("LLM Log")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $selectedInteraction) { interaction in
            LLMLogDetailView(interaction: interaction)
        }
        .task {
            interactions = await logStore.recent(limit: 200)
        }
    }

    private func filterChip(_ feature: LLMFeature?, label: String) -> some View {
        let isSelected = selectedFeature == feature
        return Button(label) {
            selectedFeature = feature
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(isSelected ? Color.blue : Color(.secondarySystemBackground))
        .foregroundStyle(isSelected ? Color.white : Color.primary)
        .clipShape(Capsule())
    }
}

// MARK: - Row View

struct LLMLogRowView: View {
    let interaction: LLMInteraction

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(interaction.feature.rawValue)
                        .font(.subheadline.weight(.medium))
                    if !interaction.parsedSuccessfully {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                    if let toolCount = interaction.toolCallsMade?.count, toolCount > 0 {
                        Text("\(toolCount) tools")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .foregroundStyle(.blue)
                            .clipShape(Capsule())
                    }
                }
                Text(interaction.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text(interaction.model.contains("haiku") ? "haiku" : "sonnet")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                let inTok = interaction.inputTokens.map { "\($0)" } ?? "?"
                let outTok = interaction.outputTokens.map { "\($0)" } ?? "?"
                Text("\(interaction.durationMs)ms · \(inTok)/\(outTok) tok")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Detail View

struct LLMLogDetailView: View {
    let interaction: LLMInteraction
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    metaBlock
                    logSection(title: "SYSTEM PROMPT", content: interaction.systemPrompt)
                    ForEach(interaction.messages.indices, id: \.self) { i in
                        let msg = interaction.messages[i]
                        logSection(
                            title: "[\(msg.role.uppercased())]" + (msg.isInjectedContext ? " (injected context)" : ""),
                            content: msg.content
                        )
                    }
                    if let toolCalls = interaction.toolCallsMade, !toolCalls.isEmpty {
                        ForEach(toolCalls.indices, id: \.self) { i in
                            let call = toolCalls[i]
                            logSection(
                                title: "TOOL CALL: \(call.toolName) (\(call.durationMs)ms)",
                                content: "INPUT:\n\(call.input)\n\nOUTPUT:\n\(call.output)"
                            )
                        }
                    }
                    logSection(title: "RAW RESPONSE", content: interaction.rawResponse)
                }
                .padding()
            }
            .navigationTitle(interaction.feature.rawValue)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    ShareLink(item: exportText) {
                        Label("Export", systemImage: "square.and.arrow.up")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var metaBlock: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(interaction.timestamp.formatted(date: .complete, time: .standard))
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                Text(interaction.model)
                    .font(.caption)
                Text("·")
                Text("\(interaction.durationMs)ms")
                    .font(.caption)
                Text("·")
                let inTok = interaction.inputTokens.map { "\($0) in" } ?? "? in"
                let outTok = interaction.outputTokens.map { "\($0) out" } ?? "? out"
                Text("\(inTok) / \(outTok)")
                    .font(.caption)
            }
            .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                if interaction.parsedSuccessfully {
                    Label("Parsed OK", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                } else {
                    Label("Parse failed", systemImage: "xmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if interaction.iterationCount > 1 {
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(interaction.iterationCount) iterations")
                        .font(.caption)
                        .foregroundStyle(.blue)
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(.secondarySystemBackground)))
    }

    private func logSection(title: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(content)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
        }
    }

    private var exportText: String {
        var lines: [String] = [
            "=== \(interaction.feature.rawValue.uppercased()) ===",
            "Timestamp: \(interaction.timestamp)",
            "Model: \(interaction.model)",
            "Duration: \(interaction.durationMs)ms",
            "Tokens: \(interaction.inputTokens ?? 0) in / \(interaction.outputTokens ?? 0) out",
            "Parsed: \(interaction.parsedSuccessfully)",
            "Iterations: \(interaction.iterationCount)",
            "",
            "--- SYSTEM PROMPT ---",
            interaction.systemPrompt
        ]
        for msg in interaction.messages {
            lines += ["", "--- [\(msg.role.uppercased())] ---", msg.content]
        }
        if let toolCalls = interaction.toolCallsMade {
            for call in toolCalls {
                lines += [
                    "", "--- TOOL: \(call.toolName) (\(call.durationMs)ms) ---",
                    "INPUT: \(call.input)",
                    "OUTPUT: \(call.output)"
                ]
            }
        }
        lines += ["", "--- RAW RESPONSE ---", interaction.rawResponse]
        return lines.joined(separator: "\n")
    }
}
