import SwiftUI

struct WeeklyReviewView: View {
    let viewModel: WeeklyReviewViewModel

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else if let review = viewModel.review {
                    reviewContent(review)
                } else if let fallback = viewModel.rawFallbackText {
                    fallbackView(fallback)
                } else if let error = viewModel.error {
                    errorView(message: error.userMessage)
                } else {
                    generatePrompt
                }
            }
            .navigationTitle("Weekly Review")
            .navigationBarTitleDisplayMode(.inline)
            .task { viewModel.tryLoadCache() }
        }
    }

    // MARK: - State Views

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Analyzing your week…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private var generatePrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "calendar.badge.checkmark")
                .font(.system(size: 52))
                .foregroundStyle(.blue)
            Text("Weekly Coaching Review")
                .font(.title3.weight(.semibold))
            Text("A Sonnet-powered analysis of your 7-day trends, goal pace, and what to focus on next week.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Generate Review") {
                Task { await viewModel.generate() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func fallbackView(_ text: String) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Label("Could not parse structured response", systemImage: "exclamationmark.circle")
                    .font(.caption.weight(.medium)).foregroundStyle(.orange)
                Text(text).font(.body)
                Button("Retry") { Task { await viewModel.generate() } }
                    .buttonStyle(.bordered)
            }
            .padding()
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark").font(.system(size: 36)).foregroundStyle(.red)
            Text(message).font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Button("Retry") { Task { await viewModel.generate() } }.buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }

    // MARK: - Review Content

    @ViewBuilder
    private func reviewContent(_ review: WeeklyReviewResponse) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {

                // 1. Header — week label + overall summary
                headerCard(review)

                // 2. Alerts — only when present
                if !review.alerts.isEmpty {
                    alertsCard(review.alerts)
                }

                // 3. Key Metrics
                metricsCard(review.metrics)

                // 4. Activity Summary
                reviewCard(title: "Activity This Week", icon: "figure.walk") {
                    Text(review.activitySummary)
                        .font(.body)
                }

                // 5. Goal Progress
                if !review.goalProgress.isEmpty {
                    goalProgressCard(review.goalProgress)
                }

                // 6. Key Insights
                if !review.keyInsights.isEmpty {
                    reviewCard(title: "Key Insights", icon: "lightbulb.fill") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(review.keyInsights, id: \.self) { insight in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("•").foregroundStyle(.secondary)
                                    Text(insight).font(.callout)
                                }
                            }
                        }
                    }
                }

                // 7. Next Week Priorities
                if !review.nextWeekPriorities.isEmpty {
                    reviewCard(title: "Next Week Priorities", icon: "checklist") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(Array(review.nextWeekPriorities.enumerated()), id: \.offset) { i, priority in
                                HStack(alignment: .top, spacing: 8) {
                                    Text("\(i + 1).")
                                        .font(.callout.weight(.semibold))
                                        .foregroundStyle(.blue)
                                        .frame(width: 20, alignment: .leading)
                                    Text(priority).font(.callout)
                                }
                            }
                        }
                    }
                }

                // 8. Week Focus
                weekFocusCard(review.weekFocus)

                // Footer: generated timestamp + regenerate
                VStack(spacing: 8) {
                    if let date = viewModel.generatedAt {
                        let fmt = DateFormatter()
                        let _ = { fmt.dateStyle = .medium; fmt.timeStyle = .short }()
                        Text("Generated \(fmt.string(from: date))\(viewModel.isFromCache ? " · cached" : "")")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    Button("Regenerate") {
                        Task { await viewModel.regenerate() }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    // MARK: - Section Cards

    private func headerCard(_ review: WeeklyReviewResponse) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(review.weekLabel)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .tracking(0.5)
            Text(review.overallSummary)
                .font(.body)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func alertsCard(_ alerts: [WeeklyReviewAlert]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Alerts", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.orange)
            ForEach(alerts, id: \.metric) { alert in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: alert.severity == "alert" ? "xmark.circle.fill" : "exclamationmark.circle.fill")
                        .foregroundStyle(alert.severity == "alert" ? .red : .orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(alert.metric)
                            .font(.caption.weight(.semibold))
                        Text(alert.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.orange.opacity(0.25), lineWidth: 1))
    }

    private func metricsCard(_ metrics: [WeeklyMetricEntry]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Key Metrics", systemImage: "waveform.path.ecg")
                .font(.subheadline.weight(.semibold))
            ForEach(metrics, id: \.metric) { entry in
                metricRow(entry)
                if entry.metric != metrics.last?.metric {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func metricRow(_ entry: WeeklyMetricEntry) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(entry.metric)
                    .font(.subheadline.weight(.medium))
                Spacer()
                trendBadge(entry.trend)
            }
            HStack(spacing: 0) {
                statCell(label: "Avg", value: formatValue(entry.avg, unit: entry.unit))
                Divider().frame(height: 28).padding(.horizontal, 10)
                statCell(label: "Min", value: formatValue(entry.min, unit: entry.unit))
                Divider().frame(height: 28).padding(.horizontal, 10)
                statCell(label: "Max", value: formatValue(entry.max, unit: entry.unit))
            }
            Text(entry.vsBaseline)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.callout.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 48)
    }

    private func trendBadge(_ trend: String) -> some View {
        let (icon, color, label) = trendStyle(trend)
        return HStack(spacing: 3) {
            Image(systemName: icon).font(.caption2)
            Text(label).font(.caption2.weight(.semibold))
        }
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(color.opacity(0.12))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private func goalProgressCard(_ progress: [GoalProgressNote]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Goal Progress", systemImage: "target")
                .font(.subheadline.weight(.semibold))
            ForEach(progress, id: \.metricLabel) { note in
                goalProgressRow(note)
                if note.metricLabel != progress.last?.metricLabel {
                    Divider()
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    private func goalProgressRow(_ note: GoalProgressNote) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(note.metricLabel)
                    .font(.subheadline.weight(.medium))
                Spacer()
                let (label, color) = paceStyle(note.pace)
                Text(label)
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(color.opacity(0.15))
                    .foregroundStyle(color)
                    .clipShape(Capsule())
            }
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("This week")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", note.thisWeekAvg))
                        .font(.callout.weight(.semibold))
                }
                let delta = note.deltaFromLastWeek
                VStack(alignment: .leading, spacing: 1) {
                    Text("vs last week")
                        .font(.caption2).foregroundStyle(.secondary)
                    Text((delta >= 0 ? "+" : "") + String(format: "%.1f", delta))
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(delta >= 0 ? .green : .red)
                }
                Spacer()
                Text(note.phaseStatus)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
            }
            Text(note.recommendation)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func weekFocusCard(_ focus: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Week Focus", systemImage: "scope")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.blue)
            Text(focus)
                .font(.body.weight(.medium))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.blue.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.blue.opacity(0.2), lineWidth: 1))
    }

    // MARK: - Generic Card

    @ViewBuilder
    private func reviewCard<Content: View>(title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
    }

    // MARK: - Helpers

    private func trendStyle(_ trend: String) -> (String, Color, String) {
        switch trend {
        case "improving":  return ("arrow.up", .green, "Improving")
        case "stable":     return ("minus", .secondary, "Stable")
        case "declining":  return ("arrow.down", .orange, "Declining")
        case "worsening":  return ("arrow.down", .red, "Worsening")
        default:           return ("minus", .secondary, trend.capitalized)
        }
    }

    private func paceStyle(_ pace: String) -> (String, Color) {
        switch pace {
        case "ahead":    return ("Ahead", .green)
        case "on_track": return ("On Track", .blue)
        case "behind":   return ("Behind", .orange)
        case "stalled":  return ("Stalled", .red)
        default:         return ("On Track", .blue)
        }
    }

    private func formatValue(_ value: Double, unit: String) -> String {
        switch unit {
        case "hours": return String(format: "%.1f", value)
        default:      return String(format: "%.0f", value)
        }
    }
}
