import SwiftUI
import UniformTypeIdentifiers

struct TrainerView: View {
    @State private var viewModel = TrainerViewModel()
    @State private var showFilePicker = false

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.profile == nil {
                    noProfileView
                } else if viewModel.currentPlan == nil {
                    noPlanView
                } else {
                    mainView
                }
            }
            .navigationTitle("Coach")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                if viewModel.profile != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Edit Profile") { viewModel.showSetup = true }
                            Button("Refresh Plan") {
                                Task { await viewModel.refreshPlan() }
                            }
                            Divider()
                            Button("Upload Program") { showFilePicker = true }
                            if viewModel.uploadedProgramName != nil {
                                Button("Analyze Uploaded Program") {
                                    Task { await viewModel.generatePlanFromUpload() }
                                }
                                Button("Clear Uploaded Program", role: .destructive) {
                                    Task { await viewModel.clearUploadedProgram() }
                                }
                            }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showSetup) {
                TrainerSetupView(viewModel: viewModel)
            }
            .sheet(item: $viewModel.selectedWorkout) { workout in
                WorkoutDetailView(workout: workout, viewModel: viewModel)
            }
            .sheet(item: $viewModel.workoutToLog) { workout in
                WorkoutLogView(workout: workout, viewModel: viewModel)
            }
            .fileImporter(
                isPresented: $showFilePicker,
                allowedContentTypes: [.plainText, .text],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    if let text = try? String(contentsOf: url, encoding: .utf8) {
                        Task {
                            await viewModel.uploadProgram(text: text, name: url.lastPathComponent)
                        }
                    }
                case .failure:
                    break
                }
            }
        }
        .task {
            await viewModel.load()
        }
    }

    // MARK: - No Profile

    private var noProfileView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("Meet Your AI Coach")
                    .font(.title2.weight(.bold))
                Text("Set up your profile and get a personalized training plan built around your goals, equipment, and recovery data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            Button {
                viewModel.showSetup = true
            } label: {
                Text("Get Started")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.blue)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            Spacer()
        }
    }

    // MARK: - Has Profile, No Plan

    private var noPlanView: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 64))
                .foregroundStyle(.blue)
            VStack(spacing: 8) {
                Text("Ready to Build Your Plan")
                    .font(.title2.weight(.bold))
                Text("Your AI coach will design a weekly training plan using your profile and current recovery data.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            if viewModel.isGeneratingPlan {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Building your plan…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button {
                    Task { await viewModel.generatePlan() }
                } label: {
                    Text("Generate My Plan")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.blue)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 32)

                // Upload program option
                VStack(spacing: 8) {
                    Text("or")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Upload Existing Program", systemImage: "doc.badge.plus")
                            .font(.subheadline)
                            .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
                    if let name = viewModel.uploadedProgramName {
                        Label(name, systemImage: "doc.text.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Analyze & Build Plan") {
                            Task { await viewModel.generatePlanFromUpload() }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.green)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 32)
                    }
                }
            }
            if let err = viewModel.error {
                Text(err.localizedDescription)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }
            Spacer()
        }
    }

    // MARK: - Main View

    private var mainView: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Today section
                todaySection

                // Week strip
                weekStripSection

                // Uploaded program indicator
                if let name = viewModel.uploadedProgramName {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.text.fill")
                            .foregroundStyle(.blue)
                        Text("Reference: \(name)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
                }

                // Agent message (after plan gen/refresh)
                if let msg = viewModel.agentMessage {
                    agentMessageCard(msg)
                }

                // Recent logs
                if !viewModel.recentLogs.isEmpty {
                    recentLogsSection
                }

                // Loading overlay
                if viewModel.isGeneratingPlan {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Updating plan…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Today Section

    @ViewBuilder
    private var todaySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Today")
                .font(.headline)

            if let workout = viewModel.todayWorkout {
                TodayWorkoutCard(workout: workout, viewModel: viewModel)
            } else if viewModel.isTodayRest {
                restDayCard
            } else {
                noWorkoutCard
            }
        }
    }

    private var restDayCard: some View {
        HStack(spacing: 14) {
            Image(systemName: "leaf.fill")
                .font(.title2)
                .foregroundStyle(.teal)
                .frame(width: 44, height: 44)
                .background(.teal.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text("Rest Day")
                    .font(.headline)
                Text("Recovery is where adaptation happens.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private var noWorkoutCard: some View {
        HStack {
            Image(systemName: "calendar")
                .foregroundStyle(.secondary)
            Text("No workout scheduled for today")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Week Strip

    private var weekStripSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("This Week")
                .font(.headline)

            if let plan = viewModel.currentPlan {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(plan.days.sorted(by: { $0.dayOfWeek < $1.dayOfWeek }), id: \.dayOfWeek) { day in
                            WeekDayChip(day: day, onTap: {
                                if let w = day.workout {
                                    viewModel.selectedWorkout = w
                                }
                            })
                        }
                    }
                    .padding(.horizontal, 2)
                }

                // Weekly focus
                if !plan.weeklyFocus.isEmpty {
                    Text(plan.weeklyFocus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                }
            }
        }
    }

    // MARK: - Recent Logs

    private var recentLogsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Workouts")
                .font(.headline)
            ForEach(viewModel.recentLogs.prefix(5)) { log in
                WorkoutLogRow(log: log)
            }
        }
    }

    // MARK: - Agent Message

    private func agentMessageCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Coach Note", systemImage: "bubble.left.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.blue)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.blue.opacity(0.07), in: RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Today Workout Card

struct TodayWorkoutCard: View {
    let workout: PlannedWorkout
    let viewModel: TrainerViewModel
    @State private var isLogged = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                workoutTypeBadge
                Spacer()
                Text("\(workout.estimatedMinutes) min")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            Text(workout.title)
                .font(.title3.weight(.bold))

            if !workout.coachNote.isEmpty {
                Text(workout.coachNote)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Divider()

            HStack(spacing: 10) {
                Button {
                    viewModel.selectedWorkout = workout
                } label: {
                    Label("View", systemImage: "doc.text")
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)

                if isLogged {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Logged")
                    }
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .foregroundStyle(.green)
                    .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Button {
                        viewModel.workoutToLog = workout
                    } label: {
                        Label("Log It", systemImage: "plus.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(.blue, in: RoundedRectangle(cornerRadius: 10))
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(16)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .onAppear { isLogged = viewModel.isTodayLogged(workout: workout) }
    }

    private var workoutTypeBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: workout.type.icon)
            Text(workout.type.label)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
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
}

// MARK: - Week Day Chip

struct WeekDayChip: View {
    let day: PlannedDay
    let onTap: () -> Void

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 6) {
                Text(dayNames[(day.dayOfWeek - 1) % 7])
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(isToday ? .white : .secondary)

                if day.isRest {
                    Image(systemName: "leaf.fill")
                        .font(.caption)
                        .foregroundStyle(isToday ? .white.opacity(0.8) : .teal)
                } else if let workout = day.workout {
                    Image(systemName: workout.type.icon)
                        .font(.caption)
                        .foregroundStyle(isToday ? .white : workoutColor(workout.type))
                } else {
                    Circle()
                        .fill(Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                }

                if !day.isRest, let workout = day.workout {
                    Text(workout.type.label)
                        .font(.system(size: 9))
                        .foregroundStyle(isToday ? .white.opacity(0.9) : .secondary)
                } else {
                    Text(day.isRest ? "Rest" : "—")
                        .font(.system(size: 9))
                        .foregroundStyle(isToday ? .white.opacity(0.9) : .secondary)
                }
            }
            .frame(width: 60, height: 80)
            .background(
                isToday ? AnyShapeStyle(.blue) : AnyShapeStyle(.regularMaterial),
                in: RoundedRectangle(cornerRadius: 12)
            )
        }
        .buttonStyle(.plain)
        .disabled(day.isRest || day.workout == nil)
    }

    private var isToday: Bool {
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        let todayDow = weekday == 1 ? 7 : weekday - 1
        return day.dayOfWeek == todayDow
    }

    private func workoutColor(_ type: WorkoutType) -> Color {
        switch type {
        case .strength:  return .blue
        case .cardio:    return .orange
        case .hiit:      return .red
        case .mobility:  return .green
        case .recovery:  return .teal
        case .mixed:     return .purple
        }
    }
}

// MARK: - Workout Log Row

struct WorkoutLogRow: View {
    let log: WorkoutLog

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: feedbackIcon)
                .font(.body)
                .foregroundStyle(feedbackColor)
                .frame(width: 36, height: 36)
                .background(feedbackColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 2) {
                Text(log.workoutTitle)
                    .font(.subheadline.weight(.medium))
                HStack(spacing: 8) {
                    Text(log.date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let rpe = log.rpe {
                        Text("RPE \(rpe)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(log.feedback.label)
                        .font(.caption)
                        .foregroundStyle(feedbackColor)
                }
            }

            Spacer()

            if let mins = log.durationMinutes {
                Text("\(mins)m")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
    }

    private var feedbackIcon: String { log.feedback.icon }

    private var feedbackColor: Color {
        switch log.feedback {
        case .tooEasy:   return .orange
        case .justRight: return .green
        case .tooHard:   return .red
        case .skipped:   return .secondary
        }
    }
}
