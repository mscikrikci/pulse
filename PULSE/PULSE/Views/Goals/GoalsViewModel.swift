import SwiftUI

@Observable
@MainActor
class GoalsViewModel {
    var goals: [GoalDefinition] = []
    var activityAlerts: [ActivityAlert] = []
    var safeZoneResults: [SafeZoneResult] = []
    var conflictWarnings: [ConflictWarning] = []
    var showSetupSheet = false
    var editingGoal: GoalDefinition?
    var error: AppError?

    private var goalStore: GoalStore?
    private var progressStore: ProgressStore?
    private var currentSummary: HealthSummary?
    private var baselines: Baselines = Baselines()

    // MARK: - Bootstrap

    func load(summary: HealthSummary?, baselines: Baselines) async {
        self.currentSummary = summary
        self.baselines = baselines
        do {
            let gs = try await GoalStore.load()
            let ps = try await ProgressStore.load()
            goalStore = gs
            progressStore = ps
            goals = await gs.goals
            activityAlerts = await gs.activityAlerts
            evaluateSafeZones()
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.storeLoadFailed(error.localizedDescription)
        }
    }

    // MARK: - Goal CRUD

    func saveGoal(_ goal: GoalDefinition) async {
        guard let store = goalStore, let pStore = progressStore else { return }
        do {
            let isNew = !goals.contains { $0.id == goal.id }
            try await store.save(goal: goal)
            if isNew { try await pStore.initializeProgress(for: goal) }
            goals = await store.goals
            conflictWarnings = GoalConflictDetector.detect(goals: goals, activityAlerts: activityAlerts)
            evaluateSafeZones()
        } catch let e as AppError {
            error = e
        } catch {
            self.error = AppError.storeSaveFailed(error.localizedDescription)
        }
    }

    func deleteGoal(id: String) async {
        guard let store = goalStore else { return }
        do {
            try await store.delete(goalId: id)
            goals = await store.goals
        } catch let e as AppError {
            error = e
        } catch {}
    }

    func saveActivityAlert(_ alert: ActivityAlert) async {
        guard let store = goalStore else { return }
        do {
            try await store.save(activityAlert: alert)
            activityAlerts = await store.activityAlerts
            conflictWarnings = GoalConflictDetector.detect(goals: goals, activityAlerts: activityAlerts)
        } catch {}
    }

    // MARK: - Progress

    func progress(for goalId: String) async -> GoalProgress? {
        await progressStore?.progress(for: goalId)
    }

    func currentPhaseRecord(for goalId: String) async -> PhaseRecord? {
        await progressStore?.progress(for: goalId)?.phaseHistory.last(where: { $0.status == "in_progress" })
    }

    // MARK: - Current metric value helpers

    func currentValue(for metric: GoalMetric) -> Double? {
        switch metric {
        case .hrv:             return currentSummary?.hrv ?? baselines.hrv7DayAvg
        case .restingHR:       return currentSummary?.restingHR ?? baselines.restingHR7DayAvg
        case .respiratoryRate: return currentSummary?.respiratoryRate ?? baselines.respiratoryRate30DayAvg
        }
    }

    func baselineValue(for metric: GoalMetric) -> Double? {
        switch metric {
        case .hrv:             return baselines.hrv30DayAvg
        case .restingHR:       return baselines.restingHR30DayAvg
        case .respiratoryRate: return baselines.respiratoryRate30DayAvg
        }
    }

    // MARK: - Private

    private func evaluateSafeZones() {
        guard let summary = currentSummary else { return }
        safeZoneResults = SafeZoneEvaluator.evaluate(
            summary: summary,
            goals: goals,
            baselines: baselines
        )
    }
}
