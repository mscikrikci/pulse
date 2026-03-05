import SwiftUI

struct GoalProgressCardView: View {
    let goal: GoalDefinition
    let progress: GoalProgress?
    let latestValue: Double?         // most recent metric value from TrendStore history
    let baselineStatus: BaselineStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if goal.mode == .target {
                targetContent
            } else {
                maintainContent
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Label(goal.metric.label, systemImage: metricIcon)
                    .font(.subheadline.weight(.semibold))
                if goal.mode == .target {
                    Text("\(goal.metric.directionSymbol) \(String(format: "%.0f", goal.targetValue)) \(goal.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Maintain baseline")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            if baselineStatus == .cold {
                Text("Establishing baseline")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.gray.opacity(0.12))
                    .clipShape(Capsule())
            } else if goal.mode == .target {
                paceBadge
            }
        }
    }

    // MARK: - Target Mode Content

    @ViewBuilder
    private var targetContent: some View {
        if let p = progress {
            // Timeline bar
            if let total = p.weeksTotal, total > 0 {
                timelineBar(elapsed: p.weeksElapsed, total: total)
            }

            // Current phase
            if let phase = p.phaseHistory.last(where: { $0.status == "in_progress" }) {
                phaseCard(phase)
            }

            // Sparkline of all weekly snapshots
            let snapshots = p.phaseHistory.flatMap { $0.weekSnapshots }
            if snapshots.count >= 2 {
                SparklineView(
                    values: snapshots.map { $0.sevenDayAvg },
                    lineColor: metricColor,
                    showFill: true
                )
                .frame(height: 44)
            }

            // Projected date + current value
            HStack {
                if let current = latestValue {
                    Text("Current: \(String(format: "%.0f", current)) \(goal.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let proj = p.projectedCompletionDate {
                    Text("Est. \(proj)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("Progress is recorded weekly. Check back after your first week.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Maintain Mode Content

    @ViewBuilder
    private var maintainContent: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("Monitoring")
                    .font(.subheadline.weight(.medium))
                if let val = latestValue {
                    Text("Latest: \(String(format: "%.0f", val)) \(goal.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Timeline Bar

    private func timelineBar(elapsed: Int, total: Int) -> some View {
        let fraction = min(Double(elapsed) / Double(total), 1.0)
        return VStack(alignment: .leading, spacing: 4) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3).fill(Color.gray.opacity(0.2)).frame(height: 6)
                    RoundedRectangle(cornerRadius: 3).fill(metricColor)
                        .frame(width: geo.size.width * CGFloat(fraction), height: 6)
                }
            }
            .frame(height: 6)
            HStack {
                Text("Week \(elapsed)")
                Spacer()
                Text("/ \(total) weeks")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - Phase Card

    private func phaseCard(_ phase: PhaseRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Phase \(phase.phase)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(metricColor)
            Text(phase.focus)
                .font(.caption)
                .foregroundStyle(.secondary)
            if phase.subTargetRange.count >= 2 {
                Text("Sub-target: \(goal.metric.directionSymbol) \(String(format: "%.0f", phase.subTargetRange[0]))–\(String(format: "%.0f", phase.subTargetRange[1])) \(goal.unit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(metricColor.opacity(0.08)))
    }

    // MARK: - Pace Badge

    private var paceBadge: some View {
        let pace = progress?.overallPace ?? "on_track"
        let (label, color) = paceStyle(pace)
        return Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private func paceStyle(_ pace: String) -> (String, Color) {
        switch pace {
        case "ahead":    return ("Ahead ↑", .green)
        case "on_track": return ("On Track", .blue)
        case "behind":   return ("Behind", .orange)
        case "stalled":  return ("Stalled", .red)
        default:         return ("On Track", .blue)
        }
    }

    // MARK: - Helpers

    private var metricIcon: String {
        switch goal.metric {
        case .hrv:             return "waveform.path.ecg"
        case .restingHR:       return "heart.fill"
        case .respiratoryRate: return "lungs.fill"
        }
    }

    private var metricColor: Color {
        switch goal.metric {
        case .hrv:             return .green
        case .restingHR:       return .red
        case .respiratoryRate: return .blue
        }
    }
}
