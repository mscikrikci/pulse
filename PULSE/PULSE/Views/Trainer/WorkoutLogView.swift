import SwiftUI

struct WorkoutLogView: View {
    let workout: PlannedWorkout
    let viewModel: TrainerViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var rpe: Double = 6
    @State private var feedback: WorkoutFeedback = .justRight
    @State private var notes: String = ""
    @State private var durationText: String = ""

    var body: some View {
        NavigationStack {
            Form {
                // Workout header
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: workout.type.icon)
                            .font(.title2)
                            .foregroundStyle(typeColor)
                            .frame(width: 44, height: 44)
                            .background(typeColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(workout.title)
                                .font(.headline)
                            Text(workout.type.label)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // How was it?
                Section("How did it go?") {
                    HStack(spacing: 0) {
                        ForEach(WorkoutFeedback.allCases, id: \.self) { option in
                            Button {
                                feedback = option
                            } label: {
                                VStack(spacing: 4) {
                                    Image(systemName: option.icon)
                                        .font(.title3)
                                        .foregroundStyle(feedback == option ? feedbackColor(option) : .secondary)
                                    Text(option.label)
                                        .font(.caption2)
                                        .foregroundStyle(feedback == option ? feedbackColor(option) : .secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(
                                    feedback == option
                                        ? feedbackColor(option).opacity(0.12)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 8)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // RPE
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Effort (RPE)")
                            Spacer()
                            Text("\(Int(rpe))/10")
                                .font(.headline)
                                .foregroundStyle(rpeColor)
                        }
                        Slider(value: $rpe, in: 1...10, step: 1)
                            .tint(rpeColor)
                        HStack {
                            Text("Easy")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("Max effort")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Duration
                Section("Duration (optional)") {
                    HStack {
                        TextField("e.g. 45", text: $durationText)
                            .keyboardType(.numberPad)
                        Text("minutes")
                            .foregroundStyle(.secondary)
                    }
                }

                // Notes
                Section("Notes (optional)") {
                    TextField("Anything worth remembering…", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Log Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .font(.headline)
                        .disabled(viewModel.isLoggingWorkout)
                }
            }
            .overlay {
                if viewModel.isLoggingWorkout {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.ultraThinMaterial)
                }
            }
        }
    }

    // MARK: - Save

    private func save() {
        let duration = Int(durationText)
        Task {
            await viewModel.logWorkout(
                workout: workout,
                rpe: Int(rpe),
                feedback: feedback,
                notes: notes.trimmingCharacters(in: .whitespacesAndNewlines),
                durationMinutes: duration
            )
            dismiss()
        }
    }

    // MARK: - Helpers

    private var typeColor: Color {
        switch workout.type {
        case .strength:  return .blue
        case .cardio:    return .orange
        case .hiit:      return .red
        case .mobility:  return .green
        case .recovery:  return .teal
        case .mixed:     return .purple
        }
    }

    private var rpeColor: Color {
        switch Int(rpe) {
        case 1...4: return .green
        case 5...7: return .orange
        default:    return .red
        }
    }

    private func feedbackColor(_ fb: WorkoutFeedback) -> Color {
        switch fb {
        case .tooEasy:   return .orange
        case .justRight: return .green
        case .tooHard:   return .red
        case .skipped:   return .secondary
        }
    }
}
