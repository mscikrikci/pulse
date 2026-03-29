import SwiftUI

struct TrainerSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let viewModel: TrainerViewModel

    // Step 1 — Level
    @State private var fitnessLevel: FitnessLevel = .intermediate
    // Step 2 — Goals
    @State private var selectedGoals: Set<TrainingGoal> = [.generalFitness]
    // Step 3 — Equipment
    @State private var selectedEquipment: Set<Equipment> = [.bodyweight]
    // Step 4 — Schedule
    @State private var daysPerWeek: Int = 4
    @State private var sessionMinutes: Int = 45
    // Step 5 — Limits
    @State private var injuries: String = ""
    @State private var preferences: String = ""

    @State private var currentStep = 0
    private let totalSteps = 5

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Progress bar
                progressBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                // Step content
                TabView(selection: $currentStep) {
                    levelStep.tag(0)
                    goalsStep.tag(1)
                    equipmentStep.tag(2)
                    scheduleStep.tag(3)
                    limitsStep.tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.25), value: currentStep)

                // Navigation buttons
                navigationButtons
                    .padding(.horizontal, 20)
                    .padding(.bottom, 24)
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(.blue)
                    .frame(width: geo.size.width * CGFloat(currentStep + 1) / CGFloat(totalSteps))
                    .animation(.easeInOut, value: currentStep)
            }
            .frame(height: 4)
        }
        .frame(height: 4)
        .padding(.bottom, 8)
    }

    // MARK: - Step Titles

    private var stepTitle: String {
        switch currentStep {
        case 0: return "Fitness Level"
        case 1: return "Your Goals"
        case 2: return "Equipment"
        case 3: return "Schedule"
        case 4: return "Limitations"
        default: return "Setup"
        }
    }

    // MARK: - Step 0: Fitness Level

    private var levelStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("How would you describe your current fitness level?")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                ForEach(FitnessLevel.allCases, id: \.self) { level in
                    Button {
                        fitnessLevel = level
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: fitnessLevel == level ? "checkmark.circle.fill" : "circle")
                                .font(.title3)
                                .foregroundStyle(fitnessLevel == level ? .blue : .secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(level.label)
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text(level.description)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .padding(16)
                        .background(
                            fitnessLevel == level
                                ? AnyShapeStyle(.blue.opacity(0.08))
                                : AnyShapeStyle(.regularMaterial),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(fitnessLevel == level ? Color.blue : Color.clear, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 20)
                }
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 1: Goals

    private var goalsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("Select all that apply — your plan will balance these priorities.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(TrainingGoal.allCases, id: \.self) { goal in
                        GoalChip(
                            goal: goal,
                            isSelected: selectedGoals.contains(goal),
                            onTap: {
                                if selectedGoals.contains(goal) {
                                    if selectedGoals.count > 1 { selectedGoals.remove(goal) }
                                } else {
                                    selectedGoals.insert(goal)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 2: Equipment

    private var equipmentStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("What do you have access to? Select everything available.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                    ForEach(Equipment.allCases, id: \.self) { item in
                        EquipmentChip(
                            equipment: item,
                            isSelected: selectedEquipment.contains(item),
                            onTap: {
                                if selectedEquipment.contains(item) {
                                    if selectedEquipment.count > 1 { selectedEquipment.remove(item) }
                                } else {
                                    selectedEquipment.insert(item)
                                }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 3: Schedule

    private var scheduleStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("How many days per week can you train?")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach(2...6, id: \.self) { days in
                            Button {
                                daysPerWeek = days
                            } label: {
                                Text("\(days)")
                                    .font(.headline)
                                    .frame(width: 50, height: 50)
                                    .background(
                                        daysPerWeek == days
                                            ? AnyShapeStyle(.blue)
                                            : AnyShapeStyle(.regularMaterial),
                                        in: RoundedRectangle(cornerRadius: 12)
                                    )
                                    .foregroundStyle(daysPerWeek == days ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("How long is each session?")
                        .font(.body)
                        .foregroundStyle(.secondary)

                    HStack(spacing: 8) {
                        ForEach([20, 30, 45, 60, 90], id: \.self) { mins in
                            Button {
                                sessionMinutes = mins
                            } label: {
                                Text("\(mins)m")
                                    .font(.subheadline.weight(.medium))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 10)
                                    .background(
                                        sessionMinutes == mins
                                            ? AnyShapeStyle(.blue)
                                            : AnyShapeStyle(.regularMaterial),
                                        in: RoundedRectangle(cornerRadius: 10)
                                    )
                                    .foregroundStyle(sessionMinutes == mins ? .white : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Step 4: Limitations

    private var limitsStep: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Help your coach avoid exercises that could cause problems.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Injuries or physical limitations")
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $injuries)
                        .frame(height: 90)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    if injuries.isEmpty {
                        Text("e.g. Lower back pain, bad left knee, shoulder impingement")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Preferences (optional)")
                        .font(.subheadline.weight(.medium))
                    TextEditor(text: $preferences)
                        .frame(height: 90)
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(Color.secondary.opacity(0.2))
                        )
                    if preferences.isEmpty {
                        Text("e.g. Prefer no running, love kettlebells, hate burpees")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Navigation Buttons

    private var navigationButtons: some View {
        HStack {
            if currentStep > 0 {
                Button("Back") {
                    currentStep -= 1
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }

            Spacer()

            if currentStep < totalSteps - 1 {
                Button("Continue") {
                    currentStep += 1
                }
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(.blue, in: Capsule())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            } else {
                Button("Save Profile") {
                    save()
                }
                .font(.headline)
                .padding(.horizontal, 28)
                .padding(.vertical, 12)
                .background(.blue, in: Capsule())
                .foregroundStyle(.white)
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Save

    private func save() {
        let now = Date()
        let profile = TrainerProfile(
            fitnessLevel: fitnessLevel,
            goals: Array(selectedGoals),
            equipment: Array(selectedEquipment),
            daysPerWeek: daysPerWeek,
            sessionMinutes: sessionMinutes,
            injuries: injuries.trimmingCharacters(in: .whitespacesAndNewlines),
            preferences: preferences.trimmingCharacters(in: .whitespacesAndNewlines),
            createdAt: viewModel.profile?.createdAt ?? now,
            updatedAt: now
        )
        Task {
            await viewModel.saveProfile(profile)
            dismiss()
        }
    }
}

// MARK: - Chip Components

private struct GoalChip: View {
    let goal: TrainingGoal
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Image(systemName: goal.icon)
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(goal.label)
                    .font(.caption.weight(.medium))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(isSelected ? .primary : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                isSelected ? AnyShapeStyle(.blue.opacity(0.1)) : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct EquipmentChip: View {
    let equipment: Equipment
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 8) {
                Image(systemName: equipment.icon)
                    .font(.subheadline)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                Text(equipment.label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(isSelected ? .primary : .secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.blue)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(
                isSelected ? AnyShapeStyle(.blue.opacity(0.08)) : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 12)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }
}
