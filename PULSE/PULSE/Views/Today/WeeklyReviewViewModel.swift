import Foundation

@Observable
@MainActor
class WeeklyReviewViewModel {
    var review: WeeklyReviewResponse?
    var rawFallbackText: String?
    var isLoading = false
    var error: AppError?
    var toolCallCount: Int = 0
    var generatedAt: Date?
    var isFromCache = false

    /// Load from cache without hitting the API. Call on view appear.
    func tryLoadCache() {
        guard review == nil, let cached = WeeklyReviewStore.loadIfCurrentWeek() else { return }
        review = cached.review
        generatedAt = cached.generatedAt
        isFromCache = true
    }

    /// Load from cache if available; generate fresh otherwise.
    func generate() async {
        if let cached = WeeklyReviewStore.loadIfCurrentWeek() {
            review = cached.review
            generatedAt = cached.generatedAt
            isFromCache = true
            return
        }
        await runGeneration()
    }

    /// Force a fresh generation, bypassing the cache.
    func regenerate() async {
        await runGeneration()
    }

    // MARK: - Private

    private func runGeneration() async {
        isLoading = true
        error = nil
        review = nil
        rawFallbackText = nil
        toolCallCount = 0
        isFromCache = false
        generatedAt = nil

        do {
            let trendStore = try await TrendStore.load()
            let goalStore = try await GoalStore.load()
            let progressStore = try await ProgressStore.load()
            let memoryStore = await MemoryStore.load()

            let baselineStatus = await trendStore.baselineStatus
            let goalCount = await goalStore.goals.count
            let memCtx = await memoryStore.buildMemoryContext()

            let frame = ContextBuilder.buildAgentFrame(
                baselineStatus: baselineStatus,
                goalCount: goalCount,
                todayEvents: [],
                memory: memCtx
            )
            let initialMessage = frame + "\n\n" + Prompts.weeklyReviewAgentInstruction

            let client = try AnthropicClient()
            let executor = ToolExecutor(trendStore: trendStore, goalStore: goalStore,
                                        progressStore: progressStore, memoryStore: memoryStore)
            let runner = AgentRunner(client: client, executor: executor)

            let result = try await runner.run(
                feature: .weeklyReview,
                system: Prompts.agentSystem,
                initialMessage: initialMessage,
                model: "claude-sonnet-4-6",
                maxTokens: 2048
            )
            toolCallCount = result.toolCallCount

            if let data = result.text.data(using: .utf8),
               let parsed = try? JSONDecoder().decode(WeeklyReviewResponse.self, from: data) {
                WeeklyReviewStore.save(parsed)
                review = parsed
                generatedAt = Date()
            } else {
                rawFallbackText = result.text
            }
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.apiFailure("Unexpected error. Please try again.")
        }

        isLoading = false
    }
}
