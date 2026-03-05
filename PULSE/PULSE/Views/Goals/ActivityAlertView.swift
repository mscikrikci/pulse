import SwiftUI

struct ActivityAlertView: View {
    @Environment(\.dismiss) private var dismiss
    let alert: ActivityAlert?
    let linkedGoals: [GoalDefinition]
    let onSave: (ActivityAlert) -> Void

    @State private var metric: String = "active_calories"
    @State private var dailyTargetText: String = "500"
    @State private var alertBelowText: String = "300"
    @State private var isEnabled: Bool = true
    @State private var linkedGoalId: String? = nil

    private let metricOptions: [(id: String, label: String, unit: String)] = [
        ("active_calories", "Active Calories", "kcal"),
        ("steps", "Daily Steps", "steps")
    ]

    var body: some View {
        NavigationStack {
            Form {
                metricSection
                thresholdSection
                optionsSection
                if let linkedNote { linkedNoteSection(linkedNote) }
            }
            .navigationTitle(alert == nil ? "New Alert" : "Edit Alert")
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
        .onAppear { loadExisting() }
    }

    // MARK: - Sections

    @ViewBuilder
    private var metricSection: some View {
        Section("Metric") {
            if alert == nil {
                Picker("Metric", selection: $metric) {
                    ForEach(metricOptions, id: \.id) { opt in
                        Text(opt.label).tag(opt.id)
                    }
                }
            } else {
                LabeledContent("Metric", value: currentLabel)
            }
        }
    }

    @ViewBuilder
    private var thresholdSection: some View {
        Section {
            HStack {
                Text("Daily Target")
                Spacer()
                TextField("e.g. 500", text: $dailyTargetText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(currentUnit)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("Alert Below")
                Spacer()
                TextField("e.g. 300", text: $alertBelowText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text(currentUnit)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Thresholds")
        } footer: {
            Text("You'll receive a nudge at 5pm if you haven't hit the alert threshold.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var optionsSection: some View {
        Section("Options") {
            Toggle("Alert Enabled", isOn: $isEnabled)
            if !linkedGoals.isEmpty {
                Picker("Linked Goal", selection: $linkedGoalId) {
                    Text("None").tag(String?.none)
                    ForEach(linkedGoals) { goal in
                        Text(goal.metric.label).tag(Optional(goal.id))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func linkedNoteSection(_ note: String) -> some View {
        Section {
            Text(note)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Why This Matters")
        }
    }

    // MARK: - Helpers

    private var currentLabel: String {
        metricOptions.first { $0.id == metric }?.label ?? metric
    }

    private var currentUnit: String {
        metricOptions.first { $0.id == metric }?.unit ?? ""
    }

    private var canSave: Bool {
        Double(dailyTargetText) != nil && Double(alertBelowText) != nil
    }

    private var linkedNote: String? {
        guard let goalId = linkedGoalId,
              let goal = linkedGoals.first(where: { $0.id == goalId }) else { return nil }
        return "Linked to your \(goal.metric.label) goal. Consistent daily activity directly supports this outcome — staying above the alert threshold keeps your training stimulus on track."
    }

    private func loadExisting() {
        guard let a = alert else { return }
        metric = a.metric
        dailyTargetText = String(Int(a.dailyTarget))
        alertBelowText = String(Int(a.alertBelow))
        isEnabled = a.isEnabled
        linkedGoalId = a.linkedGoalId
    }

    private func save() {
        guard let target = Double(dailyTargetText),
              let below = Double(alertBelowText) else { return }
        let label = currentLabel
        let note: String
        if let goalId = linkedGoalId,
           let goal = linkedGoals.first(where: { $0.id == goalId }) {
            note = "Activity supports your \(goal.metric.label) goal."
        } else {
            note = ""
        }
        let newAlert = ActivityAlert(
            metric: metric,
            label: label,
            dailyTarget: target,
            alertBelow: below,
            linkedGoalId: linkedGoalId,
            relationshipNote: note,
            isEnabled: isEnabled
        )
        onSave(newAlert)
        dismiss()
    }
}
