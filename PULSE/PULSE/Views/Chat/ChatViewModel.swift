import Foundation

@Observable
@MainActor
class ChatViewModel {

    struct Message: Identifiable {
        let id = UUID()
        let role: Role
        let content: String
        /// UI-only messages are shown in the bubble list but never sent to the API.
        var isUIOnly: Bool = false
        /// Summary shown below agentic responses ("analyzed 3 data sources").
        var toolSummary: String? = nil

        enum Role { case user, assistant }
    }

    var messages: [Message] = []
    var inputText = ""
    var isLoading = false
    var error: AppError?

    private let healthKit = HealthKitManager()
    private var currentSummary: HealthSummary?
    private var trendStore: TrendStore?
    private var goalStore: GoalStore?
    private var progressStore: ProgressStore?
    private var memoryStore: MemoryStore?
    private var morningCard: MorningCardResponse?
    private var trendStoreData: TrendStoreData?
    private var goalsContext = "No active goals set."
    private var pendingCheckInContext: String? = nil
    private var currentEvents: [String] = []
    private var currentTasks: [DailyTask] = []

    // MARK: - Bootstrap

    func loadContext() async {
        currentSummary = try? await healthKit.fetchTodaySummary()

        if let ts = try? await TrendStore.load() {
            trendStore = ts
            trendStoreData = await ts.storeData
        }
        if let gs = try? await GoalStore.load() {
            goalStore = gs
            let goals = await gs.goals
            if !goals.isEmpty {
                goalsContext = goals.map { g in
                    let detail = g.mode == .target
                        ? "target \(g.metric.directionSymbol) \(String(format: "%.0f", g.targetValue)) \(g.unit)"
                        : "maintain"
                    return "- \(g.metric.label): \(detail) (baseline \(String(format: "%.0f", g.baselineAtSet)) \(g.unit))"
                }.joined(separator: "\n")
            }
        }
        if let ps = try? await ProgressStore.load() {
            progressStore = ps
        }
        memoryStore = await MemoryStore.load()
        morningCard = MorningCardStore.loadIfToday()
        currentTasks = DailyTaskStore.loadIfToday() ?? []

        // Load today's subjective log if submitted.
        if UserDefaults.standard.string(forKey: "dailyLogDate") == TodayViewModel.todayDateKey() {
            currentEvents = UserDefaults.standard.stringArray(forKey: "dailyLogEvents") ?? []
        }
    }

    // MARK: - Send

    func send() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        inputText = ""

        messages.append(Message(role: .user, content: text))
        isLoading = true
        error = nil

        // Refresh live metrics so each message reflects current steps/calories.
        if let fresh = try? await healthKit.fetchTodaySummary() {
            currentSummary = fresh
        }

        do {
            let client = try AnthropicClient()
            let reply = try await sendAgentic(userText: text, client: client)
            messages.append(reply)
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.apiFailure("Unexpected error. Please try again.")
        }

        isLoading = false
    }

    private func sendAgentic(userText: String, client: AnthropicClient) async throws -> Message {
        guard let ts = trendStore, let gs = goalStore, let ps = progressStore else {
            // Fall back to single-shot if stores not loaded
            return try await sendSingleShot(userText: userText, client: client)
        }

        let executor = ToolExecutor(trendStore: ts, goalStore: gs, progressStore: ps,
                                    memoryStore: memoryStore)
        let runner = AgentRunner(client: client, executor: executor)

        let baselineStatus = await ts.baselineStatus
        let goalCount = await gs.goals.count
        let memCtx = await memoryStore?.buildMemoryContext(relevantTags: Set(currentEvents)) ?? .empty
        let frame = ContextBuilder.buildAgentFrame(
            baselineStatus: baselineStatus,
            goalCount: goalCount,
            todayEvents: currentEvents,
            memory: memCtx,
            dailyTasks: currentTasks
        )

        var initialMessage = frame

        // Inject today's morning card summary so the agent knows the day's context
        if let card = morningCard {
            initialMessage += """


            === TODAY'S MORNING CARD ===
            Readiness: \(card.readinessLevel) — \(card.headline)
            Summary: \(card.summary)
            Focus: \(card.oneFocus)
            Protocols suggested: \(card.protocols.map(\.id).joined(separator: ", "))
            """
        }

        // Prepend check-in context if navigating from Today tab
        if let ctx = pendingCheckInContext {
            pendingCheckInContext = nil
            initialMessage += "\n\n=== MID-DAY CHECK-IN CONTEXT ===\n\(ctx)"
        }
        initialMessage += "\n\n=== USER QUESTION ===\n\(userText)\n\n\(Prompts.chatAgentInstruction)"

        do {
            let result = try await runner.run(
                feature: .chat,
                system: Prompts.agentSystem,
                initialMessage: initialMessage,
                model: "claude-sonnet-4-6",    // always use Sonnet for agentic chat
                maxTokens: 1024
            )
            let summary = result.toolCallCount > 0
                ? "analyzed \(result.toolCallCount) data source\(result.toolCallCount == 1 ? "" : "s")"
                : nil
            return Message(role: .assistant, content: result.text, toolSummary: summary)
        } catch AppError.agentMaxIterationsReached {
            // Fall through to single-shot on agent failure
            return try await sendSingleShot(userText: userText, client: client)
        }
    }

    private func sendSingleShot(userText: String, client: AnthropicClient) async throws -> Message {
        let context = buildLegacyContext(userMessage: userText)
        let history = buildHistory()
        let reply = try await client.completeChat(context: context, history: history)
        return Message(role: .assistant, content: reply)
    }

    /// Called from the check-in "Explore in Chat" button.
    /// Loads context and pre-fills the input field — does NOT auto-send.
    func prepareContext(uiPreamble: String, checkInContext: String, prefillText: String) {
        messages.append(Message(role: .assistant, content: uiPreamble, isUIOnly: true))
        pendingCheckInContext = checkInContext
        inputText = prefillText
    }

    /// Legacy auto-send path (kept for programmatic use if needed).
    func injectAndSend(uiPreamble: String, checkInContext: String, userMessage: String) async {
        messages.append(Message(role: .assistant, content: uiPreamble, isUIOnly: true))
        pendingCheckInContext = checkInContext
        inputText = userMessage
        await send()
    }

    // MARK: - Legacy Context (fallback)

    private func buildLegacyContext(userMessage: String) -> String {
        var base: String
        if let summary = currentSummary, let trends = trendStoreData {
            base = ContextBuilder.buildChatContext(
                summary: summary,
                trends: trends,
                goals: goalsContext,
                events: currentEvents,
                userMessage: userMessage
            )
        } else {
            base = ["Health data not available.",
                    "", "=== GOALS ===", goalsContext,
                    "", "=== USER QUESTION ===", userMessage].joined(separator: "\n")
        }

        if let ctx = pendingCheckInContext {
            pendingCheckInContext = nil
            base = base.replacingOccurrences(
                of: "=== USER QUESTION ===",
                with: "=== MID-DAY CHECK-IN CONTEXT ===\n\(ctx)\n\n=== USER QUESTION ==="
            )
        }
        return base
    }

    /// All real (non-UI-only) message turns prior to the current user message.
    private func buildHistory() -> [[String: Any]] {
        messages.dropLast()
            .filter { !$0.isUIOnly }
            .map { msg in
                ["role": msg.role == .user ? "user" : "assistant",
                 "content": msg.content]
            }
    }
}
