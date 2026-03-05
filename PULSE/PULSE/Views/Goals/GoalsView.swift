import SwiftUI

struct GoalsView: View {
    @State private var viewModel = GoalsViewModel()
    @State private var showingActivityAlertSheet = false
    @State private var editingActivityAlert: ActivityAlert?

    var body: some View {
        NavigationStack {
            List {
                conflictSection
                goalsSection
                activityAlertsSection
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.editingGoal = nil
                        viewModel.showSetupSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSetupSheet) {
                GoalSetupView(viewModel: viewModel)
            }
            .sheet(isPresented: $showingActivityAlertSheet) {
                ActivityAlertView(
                    alert: editingActivityAlert,
                    linkedGoals: viewModel.goals
                ) { alert in
                    Task { await viewModel.saveActivityAlert(alert) }
                }
            }
            .alert("Error", isPresented: Binding(
                get: { viewModel.error != nil },
                set: { if !$0 { viewModel.error = nil } }
            )) {
                Button("OK") { viewModel.error = nil }
            } message: {
                Text(viewModel.error?.localizedDescription ?? "")
            }
        }
        .task {
            let ts = try? await TrendStore.load()
            let bs = await ts?.baselines ?? Baselines()
            await viewModel.load(summary: nil, baselines: bs)
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var conflictSection: some View {
        if !viewModel.conflictWarnings.isEmpty {
            Section("Conflicts Detected") {
                ForEach(viewModel.conflictWarnings) { warning in
                    VStack(alignment: .leading, spacing: 4) {
                        Label(warning.title, systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.orange)
                        Text(warning.message)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    @ViewBuilder
    private var goalsSection: some View {
        Section("Outcome Goals") {
            if viewModel.goals.isEmpty {
                ContentUnavailableView(
                    "No Goals",
                    systemImage: "target",
                    description: Text("Tap + to set your first health outcome goal.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach(viewModel.goals) { goal in
                    GoalRow(
                        goal: goal,
                        safeZoneResult: viewModel.safeZoneResults.first { $0.goalId == goal.id },
                        currentValue: viewModel.currentValue(for: goal.metric)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        viewModel.editingGoal = goal
                        viewModel.showSetupSheet = true
                    }
                }
                .onDelete { indexSet in
                    for i in indexSet {
                        let id = viewModel.goals[i].id
                        Task { await viewModel.deleteGoal(id: id) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var activityAlertsSection: some View {
        Section("Activity Alerts") {
            ForEach(viewModel.activityAlerts) { alert in
                ActivityAlertRow(alert: alert)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        editingActivityAlert = alert
                        showingActivityAlertSheet = true
                    }
            }
            Button {
                editingActivityAlert = nil
                showingActivityAlertSheet = true
            } label: {
                Label("Add Activity Alert", systemImage: "bell.badge")
            }
        }
    }
}

// MARK: - Goal Row

private struct GoalRow: View {
    let goal: GoalDefinition
    let safeZoneResult: SafeZoneResult?
    let currentValue: Double?

    var body: some View {
        HStack(spacing: 12) {
            metricIcon
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(goal.metric.label)
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    modeBadge
                }
                if goal.mode == .target {
                    Text("Target: \(goal.metric.directionSymbol) \(String(format: "%.0f", goal.targetValue)) \(goal.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let current = currentValue {
                    Text("Current: \(String(format: "%.0f", current)) \(goal.unit)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if let zone = safeZoneResult {
                safeZoneIcon(for: zone.status)
            }
        }
        .padding(.vertical, 2)
    }

    private var metricIcon: some View {
        Image(systemName: goal.metric == .hrv ? "waveform.path.ecg" :
              goal.metric == .restingHR ? "heart.fill" : "lungs.fill")
            .font(.title2)
            .foregroundStyle(metricColor)
            .frame(width: 32)
    }

    private var metricColor: Color {
        switch goal.metric {
        case .hrv:             return .green
        case .restingHR:       return .red
        case .respiratoryRate: return .blue
        }
    }

    private var modeBadge: some View {
        Text(goal.mode.label)
            .font(.caption2.weight(.medium))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(goal.mode == .target ? Color.blue.opacity(0.15) : Color.gray.opacity(0.15))
            .foregroundStyle(goal.mode == .target ? .blue : .secondary)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func safeZoneIcon(for status: SafeZoneStatus) -> some View {
        switch status {
        case .normal:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .warning:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
        case .alert:
            Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
        }
    }
}

// MARK: - Activity Alert Row

private struct ActivityAlertRow: View {
    let alert: ActivityAlert

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(alert.label)
                    .font(.subheadline.weight(.semibold))
                Text("Target: \(Int(alert.dailyTarget)) · Alert below: \(Int(alert.alertBelow))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: alert.isEnabled ? "bell.fill" : "bell.slash")
                .foregroundStyle(alert.isEnabled ? .blue : .secondary)
        }
        .padding(.vertical, 2)
    }
}
