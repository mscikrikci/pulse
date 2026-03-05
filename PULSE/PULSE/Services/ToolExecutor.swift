import Foundation

actor ToolExecutor {
    private let trendStore: TrendStore
    private let goalStore: GoalStore
    private let progressStore: ProgressStore
    private let memoryStore: MemoryStore?
    private let protocolMatcher = ProtocolMatcher()

    init(trendStore: TrendStore, goalStore: GoalStore, progressStore: ProgressStore,
         memoryStore: MemoryStore? = nil) {
        self.trendStore = trendStore
        self.goalStore = goalStore
        self.progressStore = progressStore
        self.memoryStore = memoryStore
    }

    // MARK: - Dispatch

    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        case "get_health_data":         return await getHealthData(input: input)
        case "get_trend_stats":         return await getTrendStats(input: input)
        case "get_baseline":            return await getBaseline(input: input)
        case "get_goal_progress":       return await getGoalProgress(input: input)
        case "get_protocols":           return await getProtocols(input: input)
        case "get_correlation":         return await getCorrelation(input: input)
        case "write_memory":            return await writeMemory(input: input)
        case "write_identity_summary":  return await writeIdentitySummary(input: input)
        case "add_task":                return addTask(input: input)
        default:
            return encodeError("Unknown tool: \(name)")
        }
    }

    // MARK: - Tool: get_health_data

    private func getHealthData(input: [String: Any]) async -> String {
        let history = await trendStore.history
        let fmt = dateFormatter()
        let todayKey = fmt.string(from: Date())
        let yesterdayKey = fmt.string(from: Calendar.current.date(byAdding: .day, value: -1, to: Date())!)

        var entries: [DayEntry]

        if let daysBack = input["days_back"] as? Int {
            let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, min(daysBack, 90)), to: Date())!
            let cutoffKey = fmt.string(from: cutoff)
            entries = history.filter { $0.date >= cutoffKey }
        } else if let dateStr = input["date"] as? String {
            let resolved: String
            switch dateStr {
            case "today":     resolved = todayKey
            case "yesterday": resolved = yesterdayKey
            default:          resolved = dateStr
            }
            entries = history.filter { $0.date == resolved }
        } else {
            entries = Array(history.suffix(7))
        }

        entries.sort { $0.date < $1.date }

        guard !entries.isEmpty else {
            return encode(["data_available": false, "reason": "No data found for requested window."])
        }

        return encode([
            "data_available": true,
            "days_returned": entries.count,
            "entries": entries.map { dayEntryToDict($0) }
        ])
    }

    private func dayEntryToDict(_ e: DayEntry) -> [String: Any] {
        var d: [String: Any] = ["date": e.date]
        if let v = e.hrv              { d["hrv_ms"] = round(v * 10) / 10 }
        if let v = e.restingHR        { d["resting_hr_bpm"] = round(v * 10) / 10 }
        if let v = e.sleepHours       { d["sleep_hours"] = round(v * 10) / 10 }
        if let v = e.sleepEfficiency  { d["sleep_efficiency_pct"] = Int(v * 100) }
        if let v = e.respiratoryRate  { d["respiratory_rate"] = round(v * 10) / 10 }
        if let v = e.activeCalories   { d["active_calories_kcal"] = Int(v) }
        if let v = e.steps            { d["steps"] = v }
        if let v = e.alcoholReported  { d["alcohol_reported"] = v }
        if let v = e.events, !v.isEmpty { d["events"] = v }
        // Mobility & fitness
        if let v = e.vo2Max           { d["vo2max_ml_kg_min"] = round(v * 10) / 10 }
        if let v = e.cardioRecovery   { d["cardio_recovery_bpm_drop"] = round(v * 10) / 10 }
        if let v = e.walkingHeartRate { d["walking_hr_bpm"] = round(v * 10) / 10 }
        if let v = e.walkingSpeed     { d["walking_speed_m_s"] = round(v * 100) / 100 }
        if let v = e.stairAscentSpeed { d["stair_ascent_speed_m_s"] = round(v * 100) / 100 }
        if let v = e.stairDescentSpeed { d["stair_descent_speed_m_s"] = round(v * 100) / 100 }
        return d
    }

    // MARK: - Tool: get_trend_stats

    private func getTrendStats(input: [String: Any]) async -> String {
        guard let metric = input["metric"] as? String,
              let days = input["days"] as? Int, days > 0 else {
            return encodeError("metric and days (>0) are required.")
        }

        let history = await trendStore.history
        let fmt = dateFormatter()
        let cutoffKey = fmt.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date())!)
        let window = history.filter { $0.date >= cutoffKey }
        let values: [Double] = window.compactMap { metricValue(entry: $0, metric: metric) }

        guard values.count >= 2 else {
            return encode([
                "data_available": false,
                "metric": metric,
                "days_requested": days,
                "days_available": values.count,
                "reason": "Not enough data points (need at least 2)."
            ])
        }

        let n = Double(values.count)
        let mean = values.reduce(0, +) / n
        let minVal = values.min()!
        let maxVal = values.max()!
        let variance = values.map { pow($0 - mean, 2) }.reduce(0, +) / n
        let stdDev = sqrt(variance)

        // Linear regression slope (least squares)
        let xMean = (n - 1) / 2.0
        let numerator = zip(0..., values).map { (i, v) in (Double(i) - xMean) * (v - mean) }.reduce(0, +)
        let denominator = (0..<Int(n)).map { pow(Double($0) - xMean, 2) }.reduce(0, +)
        let slope = denominator == 0 ? 0 : numerator / denominator   // units per day

        // "improving" = going in the desired direction
        let isInverseMetric = metric == "resting_hr" || metric == "respiratory_rate" || metric == "walking_hr"
        let trendNote: String
        let trendDirection: String
        let slopeThreshold = mean * 0.005   // 0.5% per day is "stable"
        if abs(slope) < slopeThreshold {
            trendDirection = "stable"
            trendNote = "No significant change over \(values.count) days (slope: \(String(format: "%.3f", slope))/day)"
        } else if slope > 0 {
            trendDirection = isInverseMetric ? "worsening" : "improving"
            trendNote = "\(isInverseMetric ? "Rising" : "Increasing") at +\(String(format: "%.2f", slope))/day over \(values.count) samples"
        } else {
            trendDirection = isInverseMetric ? "improving" : "declining"
            trendNote = "\(isInverseMetric ? "Falling" : "Decreasing") at \(String(format: "%.2f", slope))/day over \(values.count) samples"
        }

        return encode([
            "data_available": true,
            "metric": metric,
            "days_requested": days,
            "days_available": values.count,
            "mean": round(mean * 10) / 10,
            "min": round(minVal * 10) / 10,
            "max": round(maxVal * 10) / 10,
            "std_dev": round(stdDev * 10) / 10,
            "trend_direction": trendDirection,
            "trend_note": trendNote
        ])
    }

    private func metricValue(entry: DayEntry, metric: String) -> Double? {
        switch metric {
        case "hrv":                  return entry.hrv
        case "resting_hr":           return entry.restingHR
        case "respiratory_rate":     return entry.respiratoryRate
        case "sleep_hours":          return entry.sleepHours
        case "sleep_efficiency":     return entry.sleepEfficiency.map { $0 * 100 }
        case "active_calories":      return entry.activeCalories
        case "steps":                return entry.steps.map(Double.init)
        case "vo2max":               return entry.vo2Max
        case "walking_speed":        return entry.walkingSpeed
        case "walking_hr":           return entry.walkingHeartRate
        case "cardio_recovery":      return entry.cardioRecovery
        case "stair_ascent_speed":   return entry.stairAscentSpeed
        case "stair_descent_speed":  return entry.stairDescentSpeed
        default:                     return nil
        }
    }

    // MARK: - Tool: get_baseline

    private func getBaseline(input: [String: Any]) async -> String {
        let baselines = await trendStore.baselines
        let status = await trendStore.baselineStatus
        let metric = input["metric"] as? String ?? "all"

        var result: [String: Any] = [
            "data_available": true,
            "baseline_status": status.description
        ]

        func add(_ key: String, _ value: Double?) {
            result[key] = value.map { round($0 * 10) / 10 } ?? NSNull()
        }

        if metric == "all" || metric == "hrv" {
            add("hrv_7day_avg_ms", baselines.hrv7DayAvg)
            add("hrv_30day_avg_ms", baselines.hrv30DayAvg)
        }
        if metric == "all" || metric == "resting_hr" {
            add("resting_hr_7day_avg_bpm", baselines.restingHR7DayAvg)
            add("resting_hr_30day_avg_bpm", baselines.restingHR30DayAvg)
        }
        if metric == "all" || metric == "sleep_hours" {
            add("sleep_hours_7day_avg", baselines.sleepHours7DayAvg)
            add("sleep_hours_30day_avg", baselines.sleepHours30DayAvg)
        }
        if metric == "all" || metric == "sleep_efficiency" {
            if let e = baselines.sleepEfficiency30DayAvg {
                result["sleep_efficiency_30day_avg_pct"] = Int(e * 100)
            } else {
                result["sleep_efficiency_30day_avg_pct"] = NSNull()
            }
        }
        if metric == "all" || metric == "respiratory_rate" {
            add("respiratory_rate_30day_avg", baselines.respiratoryRate30DayAvg)
        }
        if metric == "all" || metric == "vo2max" {
            add("vo2max_7day_avg_ml_kg_min", baselines.vo2Max7DayAvg)
            add("vo2max_30day_avg_ml_kg_min", baselines.vo2Max30DayAvg)
        }
        if metric == "all" || metric == "walking_speed" {
            add("walking_speed_7day_avg_m_s", baselines.walkingSpeed7DayAvg)
            add("walking_speed_30day_avg_m_s", baselines.walkingSpeed30DayAvg)
        }
        if metric == "all" || metric == "walking_hr" {
            add("walking_hr_30day_avg_bpm", baselines.walkingHeartRate30DayAvg)
        }
        return encode(result)
    }

    // MARK: - Tool: get_goal_progress

    private func getGoalProgress(input: [String: Any]) async -> String {
        let goals = await goalStore.goals
        let metric = input["metric"] as? String ?? "all"

        guard !goals.isEmpty else {
            return encode(["data_available": false, "reason": "No active goals set."])
        }

        let filtered = metric == "all" ? goals : goals.filter { $0.metric.rawValue == metric }
        guard !filtered.isEmpty else {
            return encode(["data_available": false, "reason": "No goal found for metric: \(metric)"])
        }

        let goalData: [[String: Any]] = await withTaskGroup(of: [String: Any].self) { group in
            for goal in filtered {
                group.addTask { [self] in
                    await self.goalToDict(goal)
                }
            }
            var results: [[String: Any]] = []
            for await result in group { results.append(result) }
            return results
        }

        return encode(["data_available": true, "goals": goalData])
    }

    private func goalToDict(_ goal: GoalDefinition) async -> [String: Any] {
        var d: [String: Any] = [
            "id": goal.id,
            "metric": goal.metric.label,
            "unit": goal.unit,
            "mode": goal.mode.rawValue,
            "baseline_at_set": round(goal.baselineAtSet * 10) / 10,
            "current_phase": goal.currentPhase ?? 1
        ]
        if goal.mode == .target {
            d["target_value"] = round(goal.targetValue * 10) / 10
            d["timeframe_weeks"] = goal.timeframeWeeks ?? NSNull()
        }

        // Weekly snapshots directly on the goal definition
        if !goal.weeklySnapshots.isEmpty {
            let latest = goal.weeklySnapshots.last!
            d["latest_week_avg"] = round(latest.avg * 10) / 10
            d["latest_week_pace"] = latest.pace
            d["weeks_of_data"] = goal.weeklySnapshots.count
        }

        // Phase history from ProgressStore
        if let progress = await progressStore.progress(for: goal.id) {
            d["overall_pace"] = progress.overallPace
            d["weeks_elapsed"] = progress.weeksElapsed
            if let total = progress.weeksTotal { d["weeks_total"] = total }
            if let projected = progress.projectedCompletionDate { d["projected_completion"] = projected }
            if let currentPhaseRecord = progress.phaseHistory.last(where: { $0.status == "in_progress" }) {
                d["phase_focus"] = currentPhaseRecord.focus
                d["phase_sub_target_range"] = currentPhaseRecord.subTargetRange
            }
        }
        return d
    }

    // MARK: - Tool: get_protocols

    private func getProtocols(input: [String: Any]) async -> String {
        guard let conditions = input["conditions"] as? [String], !conditions.isEmpty else {
            return encodeError("conditions array is required and must not be empty.")
        }
        let maxEffort = input["max_effort"] as? String
        let matched = protocolMatcher.matchByFlags(flags: Set(conditions), maxEffort: maxEffort)

        let protocols: [[String: Any]] = matched.map { p in
            return [
                "id": p.id,
                "title": p.title,
                "description": p.protocolDescription,
                "effort": p.effort,
                "duration_minutes": p.durationMinutes
            ]
        }

        return encode(["data_available": true, "count": protocols.count, "protocols": protocols])
    }

    // MARK: - Tool: get_correlation

    private func getCorrelation(input: [String: Any]) async -> String {
        guard let metricA = input["metric_a"] as? String,
              let metricB = input["metric_b"] as? String,
              let days = input["days"] as? Int, days >= 5 else {
            return encodeError("metric_a, metric_b, and days (≥5) are required.")
        }

        let history = await trendStore.history
        let fmt = dateFormatter()
        let cutoffKey = fmt.string(from: Calendar.current.date(byAdding: .day, value: -days, to: Date())!)
        let window = history.filter { $0.date >= cutoffKey }

        let pairs: [(Double, Double)] = window.compactMap { entry in
            guard let a = metricValue(entry: entry, metric: metricA),
                  let b = metricValue(entry: entry, metric: metricB) else { return nil }
            return (a, b)
        }

        guard pairs.count >= 5 else {
            return encode([
                "data_available": false,
                "metric_a": metricA,
                "metric_b": metricB,
                "reason": "Insufficient paired data: \(pairs.count) days with both metrics (need 5+)."
            ])
        }

        let n = Double(pairs.count)
        let meanA = pairs.map(\.0).reduce(0, +) / n
        let meanB = pairs.map(\.1).reduce(0, +) / n
        let cov = pairs.map { ($0.0 - meanA) * ($0.1 - meanB) }.reduce(0, +) / n
        let stdA = sqrt(pairs.map { pow($0.0 - meanA, 2) }.reduce(0, +) / n)
        let stdB = sqrt(pairs.map { pow($0.1 - meanB, 2) }.reduce(0, +) / n)
        let pearson = (stdA * stdB) == 0 ? 0.0 : cov / (stdA * stdB)
        let r = round(pearson * 100) / 100

        let direction: String
        let interpretation: String
        if r > 0.3 {
            direction = "positive"
            interpretation = "\(metricA) and \(metricB) tend to move together (r=\(r)). Higher \(metricA) associates with higher \(metricB)."
        } else if r < -0.3 {
            direction = "negative"
            interpretation = "\(metricA) and \(metricB) tend to move opposite (r=\(r)). Higher \(metricA) associates with lower \(metricB)."
        } else {
            direction = "none"
            interpretation = "No meaningful correlation found between \(metricA) and \(metricB) (r=\(r))."
        }

        let examples = pairs.prefix(5).enumerated().map { i, pair in
            ["day_\(i+1)": [metricA: pair.0, metricB: pair.1]] as [String: Any]
        }

        return encode([
            "data_available": true,
            "metric_a": metricA,
            "metric_b": metricB,
            "sample_days": pairs.count,
            "pearson_r": r,
            "direction": direction,
            "interpretation": interpretation,
            "example_pairs": examples
        ])
    }

    // MARK: - Tool: write_memory

    private func writeMemory(input: [String: Any]) async -> String {
        guard let store = memoryStore else {
            return encode(["written": false, "reason": "Memory store not available."])
        }
        guard let type = input["type"] as? String,
              let content = input["content"] as? String,
              let tags = input["tags"] as? [String],
              let importance = input["importance"] as? String else {
            return encodeError("type, content, tags, and importance are required.")
        }
        let source = input["source"] as? String ?? "unknown"
        let id = await store.writeEpisodic(type: type, content: content, tags: tags,
                                           importance: importance, source: source)
        return encode(["written": true, "id": id])
    }

    // MARK: - Tool: write_identity_summary

    private func writeIdentitySummary(input: [String: Any]) async -> String {
        guard let store = memoryStore else {
            return encode(["written": false, "reason": "Memory store not available."])
        }
        guard let summary = input["summary"] as? String,
              let sensitivities = input["key_sensitivities"] as? [String],
              let strengths = input["key_strengths"] as? [String],
              let focus = input["active_focus"] as? String else {
            return encodeError("summary, key_sensitivities, key_strengths, and active_focus are required.")
        }
        await store.writeIdentitySummary(
            summary: summary,
            keySensitivities: sensitivities,
            keyStrengths: strengths,
            activeFocus: focus
        )
        return encode(["written": true])
    }

    // MARK: - Tool: add_task

    private func addTask(input: [String: Any]) -> String {
        guard let title = input["title"] as? String, !title.isEmpty else {
            return encodeError("title is required and must not be empty.")
        }
        let protocolId = input["protocol_id"] as? String
        var tasks = DailyTaskStore.loadIfToday() ?? []
        let task = DailyTask(source: "chat", title: title, protocolId: protocolId, createdAt: Date())
        tasks.append(task)
        DailyTaskStore.save(tasks)
        return encode(["added": true, "task_id": task.id.uuidString, "title": title])
    }

    // MARK: - Helpers

    private func encode(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }

    private func encodeError(_ message: String) -> String {
        encode(["error": message, "data_available": false])
    }

    private func dateFormatter() -> DateFormatter {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
