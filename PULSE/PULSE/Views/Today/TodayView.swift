import SwiftUI

struct TodayView: View {
    var onOpenChat: ((PendingChatContext) -> Void)? = nil

    @State private var viewModel = TodayViewModel()
    @State private var weeklyReviewVM = WeeklyReviewViewModel()
    @State private var showWeeklyReview = false

    // Daily log ephemeral state
    @State private var pendingAlcohol: Bool? = nil
    @State private var selectedEvents: Set<String> = []
    @State private var customEventInput: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {

                    // Safe zone alerts
                    if !viewModel.safeZoneAlerts.isEmpty {
                        AlertBannerView(alerts: viewModel.safeZoneAlerts)
                            .padding(.horizontal)
                    }

                    // Morning card or loading or generate button
                    Group {
                        if viewModel.isLoading {
                            loadingCard
                        } else if let card = viewModel.morningCard {
                            MorningCardView(card: card)
                                .padding(.horizontal)
                        } else if let fallback = viewModel.rawFallbackText {
                            fallbackCard(text: fallback)
                        } else if let error = viewModel.error {
                            errorCard(message: error.userMessage)
                        } else {
                            generateButton
                        }
                    }

                    // Today's actions (shown when tasks exist)
                    if !viewModel.dailyTasks.isEmpty {
                        todayActionsCard
                    }

                    // Mid-day check-in (always shown when health data is loaded)
                    if viewModel.currentSummary != nil {
                        checkInCard
                    }

                    // Daily log card (always shown when health data is loaded)
                    if viewModel.currentSummary != nil {
                        dailyLogCard
                    }

                    // Weekly review card
                    weeklyReviewCard
                }
                .padding(.vertical)
            }
            .navigationTitle("Today")
            .sheet(isPresented: $showWeeklyReview) {
                WeeklyReviewView(viewModel: weeklyReviewVM)
            }
            .task {
                await viewModel.bootstrap()
                weeklyReviewVM.tryLoadCache()
            }
            .onAppear {
                viewModel.refreshTasks()
            }
        }
    }

    // MARK: - Subviews

    private var loadingCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(width: 80, height: 24)
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.2)).frame(maxWidth: .infinity).frame(height: 20)
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)).frame(maxWidth: .infinity).frame(height: 60)
            RoundedRectangle(cornerRadius: 8).fill(Color.gray.opacity(0.15)).frame(maxWidth: .infinity).frame(height: 80)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
        .redacted(reason: .placeholder)
    }

    private var generateButton: some View {
        VStack(spacing: 12) {
            Image(systemName: "sun.max.circle")
                .font(.system(size: 48))
                .foregroundStyle(.yellow)
            Text("Tap to generate your readiness report")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Button("Generate Morning Card") {
                Task { await viewModel.generateMorningCard() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
    }

    private func fallbackCard(text: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Could not parse structured response", systemImage: "exclamationmark.circle")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
            Text(text)
                .font(.body)
            Button("Retry") {
                Task { await viewModel.generateMorningCard() }
            }
            .buttonStyle(.bordered)
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
    }

    private func errorCard(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 36))
                .foregroundStyle(.red)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Retry") {
                Task { await viewModel.generateMorningCard() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
    }

    @ViewBuilder
    private var checkInCard: some View {
        if let result = viewModel.checkIn {
            // Show check-in result
            VStack(alignment: .leading, spacing: 10) {
                Label(result.headline, systemImage: "arrow.trianglehead.clockwise")
                    .font(.subheadline.weight(.semibold))
                Text(result.observation)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                Text(result.suggestion)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                HStack(spacing: 10) {
                    Button("Explore in Chat →") {
                        let preamble = "**Mid-day check-in:**\n\(result.observation)\n\n💡 *\(result.suggestion)*"
                        var apiContext = ""
                        if let card = viewModel.morningCard {
                            apiContext += "Morning readiness: \(card.readinessLevel) — \(card.headline)\n"
                            apiContext += "Morning focus: \(card.oneFocus)\n\n"
                        }
                        apiContext += "Check-in observation: \(result.observation)\n"
                        apiContext += "Suggestion given: \(result.suggestion)"
                        onOpenChat?(PendingChatContext(
                            uiPreamble: preamble,
                            checkInContext: apiContext,
                            prefillText: result.chatPrompt
                        ))
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.blue)
                    Button("Refresh") {
                        Task { await viewModel.generateCheckIn() }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal)
        } else {
            // Show "Check In" trigger button
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("How's the day going?")
                        .font(.subheadline.weight(.medium))
                    Text("Compare now to your morning reading")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    Task { await viewModel.generateCheckIn() }
                } label: {
                    if viewModel.isCheckingIn {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Check In")
                            .font(.subheadline.weight(.medium))
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCheckingIn)
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .padding(.horizontal)
        }
    }

    // MARK: - Today's Actions Card

    private var todayActionsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Today's Actions")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                let done = viewModel.dailyTasks.filter(\.isCompleted).count
                let total = viewModel.dailyTasks.count
                Text("\(done)/\(total)")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(done == total ? .green : .secondary)
            }

            ForEach(viewModel.dailyTasks) { task in
                Button {
                    viewModel.toggleTask(id: task.id)
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(task.isCompleted ? .green : .secondary)
                            .font(.system(size: 18))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(task.title)
                                .font(.subheadline)
                                .foregroundStyle(task.isCompleted ? .secondary : .primary)
                                .strikethrough(task.isCompleted)
                                .multilineTextAlignment(.leading)
                            HStack(spacing: 6) {
                                if let pid = task.protocolId {
                                    Text(pid)
                                        .font(.caption2)
                                        .foregroundStyle(.blue)
                                }
                                if task.source == "chat" {
                                    Text("from Chat")
                                        .font(.caption2)
                                        .foregroundStyle(.purple)
                                }
                            }
                        }
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
    }

    // MARK: - Daily Log Card
    // Alcohol is one-time per day (locked after answered).
    // Events are always open — user can add/change at any time throughout the day.

    @ViewBuilder
    private var dailyLogCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Daily Log")
                .font(.subheadline.weight(.semibold))

            // Alcohol — locked once answered, open otherwise
            if viewModel.alcoholCheckedToday {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Alcohol: logged for today")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Any alcohol yesterday?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        Button("No") { pendingAlcohol = false }
                            .buttonStyle(.bordered)
                            .tint(pendingAlcohol == false ? .green : nil)
                        Button("Yes") { pendingAlcohol = true }
                            .buttonStyle(.bordered)
                            .tint(pendingAlcohol == true ? .orange : nil)
                    }
                }
            }

            Divider()

            // Events — always open, accumulates throughout the day
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("How are you feeling?")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !viewModel.todayEvents.isEmpty {
                        Text("\(viewModel.todayEvents.count) logged")
                            .font(.caption2)
                            .foregroundStyle(.blue)
                    }
                }
                FlowLayout(spacing: 8) {
                    ForEach(SubjectiveEvent.allCases, id: \.rawValue) { event in
                        let selected = selectedEvents.contains(event.rawValue)
                            || viewModel.todayEvents.contains(event.rawValue)
                        Button(event.label) {
                            if selected {
                                selectedEvents.remove(event.rawValue)
                            } else {
                                selectedEvents.insert(event.rawValue)
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(selected ? .blue : nil)
                        .font(.caption)
                    }
                    // Custom (free-text) events shown as removable chips
                    ForEach(customEvents, id: \.self) { custom in
                        HStack(spacing: 3) {
                            Text(custom).font(.caption)
                            Button {
                                selectedEvents.remove(custom)
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

                // Free text entry
                HStack(spacing: 8) {
                    TextField("Add a note (e.g. stressful meeting, travel)…", text: $customEventInput)
                        .font(.caption)
                        .onSubmit { submitCustomEvent() }
                    if !customEventInput.isEmpty {
                        Button("Add") { submitCustomEvent() }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.bordered)
                    }
                }
            }

            // Save button — saves alcohol (if not yet answered) and current event selection
            let hasChanges = !viewModel.alcoholCheckedToday
                ? pendingAlcohol != nil || !selectedEvents.isEmpty
                : selectedEventsChanged
            Button(viewModel.alcoholCheckedToday ? "Update Events" : "Save Log") {
                Task {
                    await viewModel.recordDailyLog(
                        alcohol: viewModel.alcoholCheckedToday ? nil : pendingAlcohol,
                        events: Array(selectedEvents)
                    )
                    // Sync UI selection to reflect merged state
                    selectedEvents = Set(viewModel.todayEvents)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(!hasChanges)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
        .onAppear {
            // Pre-populate selection with already-logged events
            selectedEvents = Set(viewModel.todayEvents)
        }
        .onChange(of: viewModel.todayEvents) { _, events in
            selectedEvents = Set(events)
        }
    }

    /// True when the current chip selection differs from what's already saved.
    private var selectedEventsChanged: Bool {
        Set(viewModel.todayEvents) != selectedEvents
    }

    /// Free-text events are those in selectedEvents that don't map to a SubjectiveEvent case.
    private var customEvents: [String] {
        selectedEvents.filter { SubjectiveEvent(rawValue: $0) == nil }.sorted()
    }

    private func submitCustomEvent() {
        let trimmed = customEventInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        selectedEvents.insert(trimmed)
        customEventInput = ""
    }

    // MARK: - Weekly Review Card

    private var weeklyReviewCard: some View {
        let isSunday = Calendar.current.component(.weekday, from: Date()) == 1
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Weekly Review", systemImage: "calendar.badge.checkmark")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if isSunday {
                    Text("Today")
                        .font(.caption2.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Color.blue.opacity(0.15))
                        .foregroundStyle(.blue)
                        .clipShape(Capsule())
                }
            }
            if weeklyReviewVM.review != nil {
                Text("Review ready — tap to read your coaching summary.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text(isSunday
                     ? "It's Sunday — a great time to review last week and plan ahead."
                     : "Generate a Sonnet-powered analysis of your 7-day trends and goal pace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(weeklyReviewVM.review != nil ? "View Review" : "Generate Weekly Review") {
                showWeeklyReview = true
            }
            .buttonStyle(.bordered)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
        .padding(.horizontal)
    }
}
