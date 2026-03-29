import SwiftUI

struct WorkoutDetailView: View {
    let workout: PlannedWorkout
    let viewModel: TrainerViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {

                    // Header
                    headerSection

                    Divider()

                    // Markdown content (primary) or structured exercises (fallback)
                    if let markdown = workout.markdownContent, !markdown.isEmpty {
                        markdownSection(markdown)
                    } else {
                        structuredSection
                    }

                    Divider()

                    // Log button
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            viewModel.workoutToLog = workout
                        }
                    } label: {
                        Label("Log This Workout", systemImage: "plus.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.blue, in: RoundedRectangle(cornerRadius: 14))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 8)
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
            .navigationTitle(workout.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                workoutTypeBadge
                Spacer()
                Label("\(workout.estimatedMinutes) min", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !workout.coachNote.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "bubble.left.fill")
                        .font(.caption)
                        .foregroundStyle(.blue)
                        .padding(.top, 2)
                    Text(workout.coachNote)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(12)
                .background(.blue.opacity(0.06), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private var workoutTypeBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: workout.type.icon)
            Text(workout.type.label)
        }
        .font(.subheadline.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(typeColor.opacity(0.15), in: Capsule())
        .foregroundStyle(typeColor)
    }

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

    // MARK: - Markdown Section

    private func markdownSection(_ markdown: String) -> some View {
        MarkdownDocumentView(markdown: markdown)
    }

    // MARK: - Structured Section (fallback)

    private var structuredSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let warmup = workout.warmup {
                workoutSection(title: "Warm-Up", systemImage: "flame", content: warmup)
            }

            if !workout.exercises.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Main Work", systemImage: "dumbbell.fill")
                        .font(.headline)
                    ForEach(workout.exercises) { exercise in
                        ExerciseRow(exercise: exercise)
                    }
                }
            }

            if let cooldown = workout.cooldown {
                workoutSection(title: "Cool-Down", systemImage: "leaf.fill", content: cooldown)
            }
        }
    }

    private func workoutSection(title: String, systemImage: String, content: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            Text(content)
                .font(.body)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Exercise Row

struct ExerciseRow: View {
    let exercise: ExerciseItem

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(Color.blue.opacity(0.15))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(exercise.name)
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 10) {
                    if let sets = exercise.sets {
                        pill("\(sets) sets", color: .blue)
                    }
                    if let reps = exercise.reps {
                        pill(reps + " reps", color: .purple)
                    }
                    if let duration = exercise.duration {
                        pill(duration, color: .orange)
                    }
                    if let rest = exercise.rest {
                        pill("Rest \(rest)", color: .secondary)
                    }
                }

                if let weight = exercise.weight {
                    Text(weight)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let notes = exercise.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .italic()
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func pill(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12), in: Capsule())
            .foregroundStyle(color == .secondary ? Color.secondary : color)
    }
}
