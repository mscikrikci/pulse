import SwiftUI

@Observable
@MainActor
class TrainerViewModel {
    var profile: TrainerProfile?
    var currentPlan: WeeklyPlan?
    var recentLogs: [WorkoutLog] = []
    var isGeneratingPlan = false
    var isLoggingWorkout = false
    var error: AppError?
    var agentMessage: String?           // last message from trainer agent

    // Sheet routing
    var showSetup = false
    var selectedWorkout: PlannedWorkout?   // set to show WorkoutDetailView
    var workoutToLog: PlannedWorkout?      // set to show WorkoutLogView

    private var trainerStore: TrainerStore?
    private var trendStore: TrendStore?

    // MARK: - Bootstrap

    func load() async {
        do {
            let ts = try await TrendStore.load()
            trendStore = ts
            let store = try await TrainerStore.load()
            trainerStore = store
            profile = await store.profile
            currentPlan = await store.currentPlan
            recentLogs = await store.recentLogs(limit: 10)
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.storeLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Profile

    func saveProfile(_ profile: TrainerProfile) async {
        guard let store = trainerStore else { return }
        do {
            try await store.saveProfile(profile)
            self.profile = profile
        } catch let e as AppError {
            error = e
        } catch {}
    }

    // MARK: - Plan Generation

    func generatePlan() async {
        guard let trainerStore, let trendStore else { return }
        isGeneratingPlan = true
        error = nil
        agentMessage = nil

        do {
            let client = try AnthropicClient()
            let executor = TrainerToolExecutor(trainerStore: trainerStore, trendStore: trendStore)
            let runner = TrainerAgentRunner(client: client, executor: executor)

            let result = try await runner.run(
                instruction: TrainerPrompts.generatePlanInstruction,
                system: TrainerPrompts.system
            )
            agentMessage = result.text
            currentPlan = await trainerStore.currentPlan
            recentLogs = await trainerStore.recentLogs(limit: 10)
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.agentMaxIterationsReached
        }

        isGeneratingPlan = false
    }

    func refreshPlan() async {
        guard let trainerStore, let trendStore else { return }
        isGeneratingPlan = true
        error = nil
        agentMessage = nil

        do {
            let client = try AnthropicClient()
            let executor = TrainerToolExecutor(trainerStore: trainerStore, trendStore: trendStore)
            let runner = TrainerAgentRunner(client: client, executor: executor)

            let result = try await runner.run(
                instruction: TrainerPrompts.refreshPlanInstruction,
                system: TrainerPrompts.system
            )
            agentMessage = result.text
            currentPlan = await trainerStore.currentPlan
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.agentMaxIterationsReached
        }

        isGeneratingPlan = false
    }

    // MARK: - Chat

    func sendChatMessage(_ userMessage: String) async -> String {
        guard let trainerStore, let trendStore else { return "Not ready." }
        do {
            let client = try AnthropicClient()
            let executor = TrainerToolExecutor(trainerStore: trainerStore, trendStore: trendStore)
            let runner = TrainerAgentRunner(client: client, executor: executor)

            let result = try await runner.run(
                instruction: TrainerPrompts.chatInstruction + "\n\nUser: \(userMessage)",
                system: TrainerPrompts.system
            )
            // Reload plan in case chat triggered an update
            currentPlan = await trainerStore.currentPlan
            return result.text
        } catch {
            return "Something went wrong. Please try again."
        }
    }

    // MARK: - Workout Logging

    func logWorkout(
        workout: PlannedWorkout,
        rpe: Int?,
        feedback: WorkoutFeedback,
        notes: String,
        durationMinutes: Int?
    ) async {
        guard let store = trainerStore, let trendStore else { return }
        isLoggingWorkout = true

        let history = await trendStore.history
        let today = history.sorted { $0.date < $1.date }.last
        let baselines = await trendStore.baselines

        var readinessTag: String? = nil
        if let hrv = today?.hrv, let avg30 = baselines.hrv30DayAvg, avg30 > 0 {
            let pct = (hrv - avg30) / avg30
            readinessTag = pct >= -0.1 ? (pct >= 0.1 ? "high" : "medium") : "low"
        }

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"

        let log = WorkoutLog(
            id: UUID().uuidString,
            date: df.string(from: Date()),
            workoutId: workout.id,
            workoutTitle: workout.title,
            workoutType: workout.type,
            completedAt: Date(),
            durationMinutes: durationMinutes,
            rpe: rpe,
            feedback: feedback,
            notes: notes,
            hrvAtLog: today?.hrv,
            sleepHoursLastNight: today?.sleepHours,
            readinessTag: readinessTag
        )

        do {
            try await store.logWorkout(log)
            recentLogs = await store.recentLogs(limit: 10)
            workoutToLog = nil
        } catch let e as AppError {
            error = e
        } catch {}

        isLoggingWorkout = false
    }

    // MARK: - Helpers

    var todayWorkout: PlannedWorkout? {
        guard let plan = currentPlan else { return nil }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        // Convert: 1=Sun, 2=Mon... → 1=Mon...7=Sun
        let dayOfWeek = weekday == 1 ? 7 : weekday - 1
        return plan.days.first(where: { $0.dayOfWeek == dayOfWeek && !$0.isRest })?.workout
    }

    var isTodayRest: Bool {
        guard let plan = currentPlan else { return false }
        let cal = Calendar.current
        let weekday = cal.component(.weekday, from: Date())
        let dayOfWeek = weekday == 1 ? 7 : weekday - 1
        return plan.days.first(where: { $0.dayOfWeek == dayOfWeek })?.isRest ?? false
    }

    func isTodayLogged(workout: PlannedWorkout) -> Bool {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let todayKey = df.string(from: Date())
        return recentLogs.contains { $0.workoutId == workout.id && $0.date == todayKey }
    }
}

// MARK: - TrainerAgentRunner

/// Thin agent loop for trainer — same pattern as AgentRunner but with TrainerToolExecutor.
actor TrainerAgentRunner {
    private let client: AnthropicClient
    private let executor: TrainerToolExecutor
    private let maxIterations = 6

    init(client: AnthropicClient, executor: TrainerToolExecutor) {
        self.client = client
        self.executor = executor
    }

    func run(instruction: String, system: String) async throws -> AgentResult {
        var messages: [[String: Any]] = [["role": "user", "content": instruction]]
        var allToolNames: [String] = []

        for _ in 0..<maxIterations {
            let response = try await client.completeWithTools(
                system: system,
                messages: messages,
                tools: TrainerTools.definitions,
                model: "claude-sonnet-4-6",
                maxTokens: 4096
            )

            if response.toolCalls.isEmpty {
                return AgentResult(
                    text: response.text,
                    toolCallCount: allToolNames.count,
                    toolsSummary: allToolNames
                )
            }

            messages.append(["role": "assistant", "content": response.rawContent])

            var toolResultBlocks: [[String: Any]] = []
            for call in response.toolCalls {
                allToolNames.append(call.name)
                let result = await executor.execute(name: call.name, input: call.input)
                toolResultBlocks.append([
                    "type": "tool_result",
                    "tool_use_id": call.id,
                    "content": result
                ])
            }
            messages.append(["role": "user", "content": toolResultBlocks])
        }

        throw AppError.agentMaxIterationsReached
    }
}
