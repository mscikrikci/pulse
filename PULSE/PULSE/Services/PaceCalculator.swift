import Foundation

enum PaceStatus: String {
    case ahead
    case onTrack = "on_track"
    case behind
    case stalled

    var label: String {
        switch self {
        case .ahead:   return "Ahead"
        case .onTrack: return "On Track"
        case .behind:  return "Behind"
        case .stalled: return "Stalled"
        }
    }
}

struct PaceCalculator {

    /// Computes pace for the current phase.
    static func computePace(
        goal: GoalDefinition,
        sevenDayAvg: Double,
        phaseRecord: PhaseRecord
    ) -> PaceStatus {
        let snapshots = phaseRecord.weekSnapshots
        guard snapshots.count >= 2,
              let subTarget = phaseRecord.subTargetRange.last,
              let baselineAtPhaseStart = phaseRecord.weekSnapshots.first?.sevenDayAvg,
              let phaseDurationWeeks = estimatePhaseDuration(phase: phaseRecord.phase) else {
            return .onTrack
        }

        let expectedWeeklyDelta = (subTarget - baselineAtPhaseStart) / Double(phaseDurationWeeks)
        guard expectedWeeklyDelta != 0 else { return .onTrack }

        let prevAvg = snapshots[snapshots.count - 1].sevenDayAvg
        let actualWeeklyDelta = sevenDayAvg - prevAvg
        let ratio = actualWeeklyDelta / expectedWeeklyDelta

        // Stalled: requires 3 consecutive weeks below 0.3 ratio
        if ratio < 0.3 {
            let recentPaces = snapshots.suffix(2).map { $0.pace }
            let allRecentStalled = recentPaces.allSatisfy { $0 == "behind" || $0 == "stalled" }
            return allRecentStalled ? .stalled : .behind
        }

        if ratio >= 1.2 { return .ahead }
        if ratio >= 0.7 { return .onTrack }
        return .behind
    }

    private static func estimatePhaseDuration(phase: Int) -> Int? {
        switch phase {
        case 1: return 3
        case 2: return 5
        case 3: return 6
        default: return nil
        }
    }
}
