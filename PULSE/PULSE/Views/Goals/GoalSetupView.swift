import SwiftUI

struct GoalSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: GoalsViewModel

    @State private var selectedMetric: GoalMetric = .hrv
    @State private var selectedMode: GoalMode = .target
    @State private var targetValueText: String = ""
    @State private var timeframeWeeks: Int = 12
    @State private var isEditing = false
    @State private var goalId: String = UUID().uuidString
    @State private var existingSnapshots: [WeeklySnapshot] = []

    var body: some View {
        NavigationStack {
            Form {
                metricSection
                modeSection
                if selectedMode == .target {
                    targetSection
                }
                referenceSection
                safeZoneSection
            }
            .navigationTitle(isEditing ? "Edit Goal" : "New Goal")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
        }
        .onAppear { loadExistingGoal() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var metricSection: some View {
        Section("Metric") {
            if isEditing {
                LabeledContent("Metric", value: selectedMetric.label)
            } else {
                Picker("Metric", selection: $selectedMetric) {
                    ForEach(GoalMetric.allCases, id: \.self) { metric in
                        Text(metric.label).tag(metric)
                    }
                }
                .onChange(of: selectedMetric) { _, _ in
                    targetValueText = ""
                }
            }
        }
    }

    @ViewBuilder
    private var modeSection: some View {
        Section {
            Picker("Mode", selection: $selectedMode) {
                ForEach(GoalMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            Group {
                switch selectedMode {
                case .target:
                    Text("Work toward a specific value with phase-based coaching over a defined timeframe.")
                case .maintain:
                    Text("Stay within safe zone of your current baseline. Alerts fire if you drift.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        } header: {
            Text("Goal Mode")
        }
    }

    @ViewBuilder
    private var targetSection: some View {
        Section {
            LabeledContent("Baseline") {
                Text(baselineDisplay)
                    .foregroundStyle(.secondary)
            }
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Target")
                    Text(selectedMetric.directionHint)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                TextField("e.g. 65", text: $targetValueText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(selectedMetric.unit)
                    .foregroundStyle(.secondary)
            }
            Stepper("Timeframe: \(timeframeWeeks) weeks", value: $timeframeWeeks, in: 4...52, step: 2)
        } header: {
            Text("Target")
        } footer: {
            Text("\(selectedMetric.directionSymbol) means improvement for this metric.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var referenceSection: some View {
        Section {
            Text(selectedMetric.referenceRangeHint)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Reference Ranges")
        }
    }

    @ViewBuilder
    private var safeZoneSection: some View {
        let config = selectedMetric.defaultSafeZone
        Section {
            if config.type == "relative" {
                if let warn = config.warningPct {
                    LabeledContent("Warning", value: "\(Int(warn))% from 30d avg")
                }
                if let alert = config.alertPct {
                    LabeledContent("Alert", value: "\(Int(alert))% from 30d avg")
                }
            } else {
                if let warn = config.warningValue {
                    LabeledContent("Warning above", value: "\(Int(warn)) \(selectedMetric.unit)")
                }
                if let alert = config.alertValue {
                    LabeledContent("Alert above", value: "\(Int(alert)) \(selectedMetric.unit)")
                }
            }
        } header: {
            Text("Safe Zone")
        } footer: {
            Text("You'll be alerted if your metric crosses these thresholds.")
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private var baselineDisplay: String {
        let val = viewModel.currentValue(for: selectedMetric)
            ?? viewModel.baselineValue(for: selectedMetric)
        guard let val else { return "Not available" }
        return "\(String(format: "%.1f", val)) \(selectedMetric.unit)"
    }

    private var canSave: Bool {
        if selectedMode == .target {
            return Double(targetValueText) != nil
        }
        return true
    }

    private func loadExistingGoal() {
        guard let goal = viewModel.editingGoal else { return }
        isEditing = true
        goalId = goal.id
        selectedMetric = goal.metric
        selectedMode = goal.mode
        targetValueText = String(format: "%.0f", goal.targetValue)
        timeframeWeeks = goal.timeframeWeeks ?? 12
        existingSnapshots = goal.weeklySnapshots
    }

    private func save() {
        let baseline = viewModel.currentValue(for: selectedMetric)
            ?? viewModel.baselineValue(for: selectedMetric)
            ?? 0.0
        let target: Double
        if selectedMode == .target {
            target = Double(targetValueText) ?? baseline
        } else {
            target = baseline
        }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let today = df.string(from: Date())
        let goal = GoalDefinition(
            id: goalId,
            metric: selectedMetric,
            label: selectedMetric.label,
            unit: selectedMetric.unit,
            direction: selectedMetric.direction,
            mode: selectedMode,
            targetValue: target,
            baselineAtSet: baseline,
            setDate: today,
            timeframeWeeks: selectedMode == .target ? timeframeWeeks : nil,
            currentPhase: selectedMode == .target ? (viewModel.editingGoal?.currentPhase ?? 1) : nil,
            phaseStartDate: selectedMode == .target ? (viewModel.editingGoal?.phaseStartDate ?? today) : nil,
            weeklySnapshots: existingSnapshots,
            safeZone: selectedMetric.defaultSafeZone
        )
        Task {
            await viewModel.saveGoal(goal)
            dismiss()
        }
    }
}
