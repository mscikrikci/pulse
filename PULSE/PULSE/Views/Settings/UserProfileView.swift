import SwiftUI

struct UserProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var ageText: String = ""
    @State private var gender: String = ""
    @State private var heightText: String = ""
    @State private var weightText: String = ""
    @State private var selectedConditions: Set<String> = []
    @State private var customConditionInput: String = ""
    @State private var savedConfirmation = false

    private let genderOptions: [(value: String, label: String)] = [
        ("male",              "Male"),
        ("female",            "Female"),
        ("other",             "Other"),
        ("prefer_not_to_say", "Prefer not to say"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                basicSection
                bodySection
                conditionsSection
            }
            .navigationTitle("Your Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                }
            }
            .alert("Profile Saved", isPresented: $savedConfirmation) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your profile will be used to personalise AI suggestions.")
            }
        }
        .onAppear { loadProfile() }
    }

    // MARK: - Sections

    private var basicSection: some View {
        Section {
            HStack {
                Text("Age")
                Spacer()
                TextField("e.g. 35", text: $ageText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("years")
                    .foregroundStyle(.secondary)
            }

            Picker("Gender", selection: $gender) {
                Text("Not set").tag("")
                ForEach(genderOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
        } header: {
            Text("About You")
        }
    }

    private var bodySection: some View {
        Section {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Height")
                    if let cm = Double(heightText), cm > 0 {
                        let ft = Int(cm / 2.54 / 12)
                        let inches = Int((cm / 2.54).truncatingRemainder(dividingBy: 12).rounded())
                        Text("\(ft)'\(inches)\"")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                TextField("e.g. 178", text: $heightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("cm")
                    .foregroundStyle(.secondary)
            }

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Weight")
                    if let kg = Double(weightText), kg > 0 {
                        let lbs = Int((kg * 2.20462).rounded())
                        Text("\(lbs) lbs")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                TextField("e.g. 75", text: $weightText)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg")
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Body Metrics")
        } footer: {
            Text("Used by the AI to contextualise protocol suggestions.")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var conditionsSection: some View {
        Section {
            FlowLayout(spacing: 8) {
                ForEach(UserProfile.predefinedConditions, id: \.id) { condition in
                    let selected = selectedConditions.contains(condition.id)
                    Button(condition.label) {
                        if selected {
                            selectedConditions.remove(condition.id)
                        } else {
                            selectedConditions.insert(condition.id)
                        }
                    }
                    .buttonStyle(.bordered)
                    .tint(selected ? .blue : nil)
                    .font(.caption)
                }

                // Custom conditions shown as removable chips
                ForEach(customConditions, id: \.self) { custom in
                    HStack(spacing: 3) {
                        Text(custom).font(.caption)
                        Button {
                            selectedConditions.remove(custom)
                        } label: {
                            Image(systemName: "xmark").font(.caption2)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Color.purple.opacity(0.12))
                    .foregroundStyle(.purple)
                    .clipShape(Capsule())
                }
            }
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                TextField("Add a condition (e.g. migraine)…", text: $customConditionInput)
                    .font(.caption)
                    .onSubmit { submitCustomCondition() }
                if !customConditionInput.isEmpty {
                    Button("Add") { submitCustomCondition() }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                }
            }
        } header: {
            Text("Health Conditions")
        } footer: {
            Text("Helps the AI avoid unsuitable protocols. This stays on your device only.")
                .font(.caption)
        }
    }

    // MARK: - Helpers

    private var customConditions: [String] {
        let predefinedIds = Set(UserProfile.predefinedConditions.map(\.id))
        return selectedConditions.filter { !predefinedIds.contains($0) }.sorted()
    }

    private func submitCustomCondition() {
        let trimmed = customConditionInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedConditions.insert(trimmed)
        customConditionInput = ""
    }

    private func loadProfile() {
        let profile = UserProfileStore.load()
        if let age = profile.age { ageText = "\(age)" }
        gender = profile.gender ?? ""
        if let cm = profile.heightCm { heightText = "\(Int(cm.rounded()))" }
        if let kg = profile.weightKg { weightText = "\(Int(kg.rounded()))" }
        selectedConditions = Set(profile.conditions)
    }

    private func save() {
        let profile = UserProfile(
            age: Int(ageText),
            gender: gender.isEmpty ? nil : gender,
            heightCm: Double(heightText),
            weightKg: Double(weightText),
            conditions: Array(selectedConditions)
        )
        UserProfileStore.save(profile)
        savedConfirmation = true
    }
}
