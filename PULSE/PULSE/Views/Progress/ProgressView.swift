import SwiftUI

// Named GoalProgressTab to avoid conflict with SwiftUI's built-in ProgressView.
struct GoalProgressTab: View {
    @State private var viewModel = GoalProgressViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.goals.isEmpty {
                    ContentUnavailableView(
                        "No Goals Yet",
                        systemImage: "chart.line.uptrend.xyaxis",
                        description: Text("Set a goal in the Goals tab to start tracking progress.")
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: 16) {
                            ForEach(viewModel.goals) { goal in
                                GoalProgressCardView(
                                    goal: goal,
                                    progress: viewModel.progressMap[goal.id],
                                    latestValue: viewModel.latestValue(for: goal.metric),
                                    baselineStatus: viewModel.baselineStatus
                                )
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Progress")
        }
        .task { await viewModel.load() }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
class GoalProgressViewModel {
    var goals: [GoalDefinition] = []
    var progressMap: [String: GoalProgress] = [:]
    var baselineStatus: BaselineStatus = .cold
    var latestHistory: [String: Double] = [:]   // metric rawValue → latest value

    func load() async {
        async let goalStoreTask = try? GoalStore.load()
        async let progressStoreTask = try? ProgressStore.load()
        async let trendStoreTask = try? TrendStore.load()

        let (gs, ps, ts) = await (goalStoreTask, progressStoreTask, trendStoreTask)

        if let gs {
            goals = await gs.goals
        }
        if let ps {
            for goal in goals {
                if let p = await ps.progress(for: goal.id) {
                    progressMap[goal.id] = p
                }
            }
        }
        if let ts {
            baselineStatus = await ts.baselineStatus
            let history = await ts.history
            if let latest = history.last {
                if let hrv = latest.hrv         { latestHistory[GoalMetric.hrv.rawValue] = hrv }
                if let rhr = latest.restingHR   { latestHistory[GoalMetric.restingHR.rawValue] = rhr }
                if let rr  = latest.respiratoryRate { latestHistory[GoalMetric.respiratoryRate.rawValue] = rr }
            }
        }
    }

    func latestValue(for metric: GoalMetric) -> Double? {
        latestHistory[metric.rawValue]
    }
}
