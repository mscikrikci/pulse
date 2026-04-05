import SwiftUI

struct HealthMetricsView: View {
    @State private var preferences = HealthMetricPreferences.shared
    @State private var enabledState: [HealthMetric: Bool] = [:]
    @State private var showResetConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            ForEach(MetricCategory.allCases, id: \.self) { category in
                let metrics = HealthMetric.allCases.filter { $0.category == category }
                Section {
                    ForEach(metrics, id: \.self) { metric in
                        metricRow(metric)
                    }
                } header: {
                    Label(category.rawValue, systemImage: category.icon)
                }
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Health Metrics")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { loadState() }
        .confirmationDialog(
            "Reset all metrics to defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                preferences.resetToDefaults()
                loadState()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func metricRow(_ metric: HealthMetric) -> some View {
        HStack(spacing: 14) {
            Image(systemName: metric.icon)
                .font(.body)
                .foregroundStyle(metric.isCoreMetric ? .blue : .secondary)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(metric.label)
                        .font(.subheadline)
                    if metric.isCoreMetric {
                        Text("Core")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                }
                Text(metric.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Toggle("", isOn: Binding(
                get: { enabledState[metric] ?? true },
                set: { newVal in
                    enabledState[metric] = newVal
                    preferences.setEnabled(metric, newVal)
                }
            ))
            .labelsHidden()
            .disabled(metric.isCoreMetric)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    private func loadState() {
        for metric in HealthMetric.allCases {
            enabledState[metric] = preferences.isEnabled(metric)
        }
    }
}
