import Foundation
import UserNotifications

actor ProgressStore {
    private var data: ProgressStoreData
    private let fileURL: URL

    private init(data: ProgressStoreData, fileURL: URL) {
        self.data = data
        self.fileURL = fileURL
    }

    static func load() async throws -> ProgressStore {
        let url = try storeURL()
        if FileManager.default.fileExists(atPath: url.path) {
            do {
                let raw = try Data(contentsOf: url)
                let decoded = try JSONDecoder().decode(ProgressStoreData.self, from: raw)
                return ProgressStore(data: decoded, fileURL: url)
            } catch {
                print("[ProgressStore] Load failed, starting fresh: \(error)")
                return ProgressStore(data: .empty(), fileURL: url)
            }
        }
        return ProgressStore(data: .empty(), fileURL: url)
    }

    // MARK: - Public API

    var storeData: ProgressStoreData { data }

    func progress(for goalId: String) -> GoalProgress? {
        data.goalProgress[goalId]
    }

    /// Called when a goal is created. Initialises the phase plan.
    func initializeProgress(for goal: GoalDefinition) throws {
        guard goal.mode == .target else { return }
        let phases = HRVPhasePlan.phases(baseline: goal.baselineAtSet, target: goal.targetValue)
        let today = dateKey(from: Date())
        let firstPhase = phases.first ?? PhaseRecord(
            phase: 1, focus: "Stabilize", startDate: today,
            subTargetRange: [goal.baselineAtSet, goal.baselineAtSet + 2],
            weekSnapshots: [], status: "in_progress"
        )
        let progress = GoalProgress(
            phaseHistory: [firstPhase],
            overallPace: "on_track",
            projectedCompletionDate: projectedDate(weeksTotal: goal.timeframeWeeks),
            weeksElapsed: 0,
            weeksTotal: goal.timeframeWeeks
        )
        data.goalProgress[goal.id] = progress
        try persist()
    }

    /// Records a weekly snapshot and checks for phase advancement.
    /// Returns true if the phase advanced.
    @discardableResult
    func recordWeeklySnapshot(
        goalId: String,
        sevenDayAvg: Double,
        baseline: Double,
        goal: GoalDefinition
    ) throws -> Bool {
        guard var progress = data.goalProgress[goalId],
              let currentPhase = progress.phaseHistory.last else { return false }

        let deltaFromBaseline = sevenDayAvg - baseline
        let pace = PaceCalculator.computePace(
            goal: goal,
            sevenDayAvg: sevenDayAvg,
            phaseRecord: currentPhase
        ).rawValue

        let snapshot = PhaseSnapshot(
            week: currentPhase.weekSnapshots.count + 1,
            sevenDayAvg: sevenDayAvg,
            deltaFromBaseline: deltaFromBaseline,
            pace: pace
        )

        let phaseIdx = progress.phaseHistory.count - 1
        progress.phaseHistory[phaseIdx].weekSnapshots.append(snapshot)
        progress.weeksElapsed += 1
        progress.overallPace = pace

        // Check phase advancement: 2 consecutive weeks at or above sub-target upper bound
        let shouldAdvance = checkAdvancement(snapshots: currentPhase.weekSnapshots + [snapshot],
                                             subTargetRange: currentPhase.subTargetRange)
        var advanced = false
        if shouldAdvance {
            progress.phaseHistory[phaseIdx].status = "completed"
            progress.phaseHistory[phaseIdx].endDate = dateKey(from: Date())
            let allPhases = HRVPhasePlan.phases(baseline: baseline, target: goal.targetValue)
            let nextPhaseNum = currentPhase.phase + 1
            if let nextTemplate = allPhases.first(where: { $0.phase == nextPhaseNum }) {
                var nextPhase = nextTemplate
                nextPhase.startDate = dateKey(from: Date())
                progress.phaseHistory.append(nextPhase)
                advanced = true
                schedulePhaseAdvancementNotification(phase: nextPhaseNum)
            }
        }

        data.goalProgress[goalId] = progress
        try persist()
        return advanced
    }

    // MARK: - Private

    private func checkAdvancement(snapshots: [PhaseSnapshot], subTargetRange: [Double]) -> Bool {
        guard subTargetRange.count >= 2, snapshots.count >= 2 else { return false }
        let upper = subTargetRange[1]
        let last2 = snapshots.suffix(2)
        return last2.allSatisfy { $0.sevenDayAvg >= upper }
    }

    private func schedulePhaseAdvancementNotification(phase: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Phase advanced!"
        content.body = "You've completed Phase \(phase - 1) of your HRV goal — entering Phase \(phase)."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)
        let request = UNNotificationRequest(
            identifier: "pulse.phase.\(phase).\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func projectedDate(weeksTotal: Int?) -> String? {
        guard let weeks = weeksTotal else { return nil }
        guard let target = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: Date()) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: target)
    }

    private func persist() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        do {
            let encoded = try encoder.encode(data)
            try encoded.write(to: fileURL, options: .atomic)
        } catch {
            throw AppError.storeSaveFailed(error.localizedDescription)
        }
    }

    private static func storeURL() throws -> URL {
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            throw AppError.storeLoadFailed("Documents directory not found")
        }
        return docs.appendingPathComponent("progress_store.json")
    }

    private func dateKey(from date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: date)
    }
}

// MARK: - HRV Phase Plan

struct HRVPhasePlan {
    static func phases(baseline: Double, target: Double) -> [PhaseRecord] {
        let gap = target - baseline
        let today = {
            let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
            return f.string(from: Date())
        }()

        return [
            PhaseRecord(
                phase: 1,
                focus: "Stabilize — consistent sleep timing, eliminate alcohol, morning sunlight",
                startDate: today,
                subTargetRange: [baseline + 1, baseline + 2],
                weekSnapshots: [],
                status: "in_progress"
            ),
            PhaseRecord(
                phase: 2,
                focus: "Build — Zone 2 cardio 2–3x/week, daily NSDR, cold exposure if tolerated",
                startDate: "",
                subTargetRange: [baseline + gap * 0.3, baseline + gap * 0.5],
                weekSnapshots: [],
                status: "pending"
            ),
            PhaseRecord(
                phase: 3,
                focus: "Optimize — training load management, meal timing, alcohol strictly minimised",
                startDate: "",
                subTargetRange: [baseline + gap * 0.8, target],
                weekSnapshots: [],
                status: "pending"
            )
        ]
    }
}
