import SwiftUI

struct MorningCardView: View {
    let card: MorningCardResponse
    @State private var expandedProtocol: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Readiness badge + headline
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    ReadinessBadge(level: card.readinessLevel)
                    Text(card.headline)
                        .font(.title3.weight(.semibold))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }

            // Summary
            Text(card.summary)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Divider()

            // Work suggestion
            Label(card.workSuggestion, systemImage: "brain.head.profile")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            // One Focus
            VStack(alignment: .leading, spacing: 6) {
                Text("ONE FOCUS")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                Text(card.oneFocus)
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.accentColor.opacity(0.1)))

            // Protocols
            if !card.protocols.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("PROTOCOLS")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    ForEach(card.protocols, id: \.id) { p in
                        ProtocolRow(suggestion: p, isExpanded: expandedProtocol == p.id) {
                            withAnimation(.spring(duration: 0.25)) {
                                expandedProtocol = expandedProtocol == p.id ? nil : p.id
                            }
                        }
                    }
                }
            }

            // Avoid today
            if !card.avoidToday.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("AVOID TODAY")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.tertiary)
                    FlowLayout(spacing: 8) {
                        ForEach(card.avoidToday, id: \.self) { item in
                            Text(item)
                                .font(.caption)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(Capsule().fill(Color.red.opacity(0.1)))
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            // Goal note
            if !card.goalNote.isEmpty && card.goalNote != "No active goals set." {
                Text(card.goalNote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }
}

// MARK: - Readiness Badge

struct ReadinessBadge: View {
    let level: String

    var color: Color {
        switch level {
        case "high":   return .green
        case "medium": return .yellow
        case "low":    return .orange
        case "alert":  return .red
        default:       return .gray
        }
    }

    var label: String { level.uppercased() }

    var body: some View {
        Text(label)
            .font(.caption.weight(.bold))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(color.opacity(0.15)))
            .foregroundStyle(color)
            .overlay(Capsule().stroke(color.opacity(0.3), lineWidth: 1))
    }
}

// MARK: - Protocol Row

struct ProtocolRow: View {
    let suggestion: ProtocolSuggestion
    let isExpanded: Bool
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onTap) {
                HStack {
                    Text(suggestion.id.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(suggestion.reason)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(.tertiarySystemBackground)))
    }
}

// MARK: - Simple Flow Layout

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 300
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > width, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
