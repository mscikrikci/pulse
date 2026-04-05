import Foundation

actor TrainerToolExecutor {
    private let trainerStore: TrainerStore
    private let trendStore: TrendStore

    init(trainerStore: TrainerStore, trendStore: TrendStore) {
        self.trainerStore = trainerStore
        self.trendStore = trendStore
    }

    // MARK: - Dispatch

    func execute(name: String, input: [String: Any]) async -> String {
        switch name {
        case "get_trainer_context":    return await getTrainerContext()
        case "write_training_plan":    return await writeTrainingPlan(input: input)
        case "update_workout_days":    return await updateWorkoutDays(input: input)
        default:
            return encode(["error": "Unknown tool: \(name)", "data_available": false])
        }
    }

    // MARK: - get_trainer_context

    private func getTrainerContext() async -> String {
        var result: [String: Any] = [:]

        // --- Profile ---
        if let profile = await trainerStore.profile {
            result["profile"] = [
                "fitness_level": profile.fitnessLevel.rawValue,
                "goals": profile.goals.map(\.rawValue),
                "equipment": profile.equipment.map(\.rawValue),
                "days_per_week": profile.daysPerWeek,
                "session_minutes": profile.sessionMinutes,
                "injuries": profile.injuries.isEmpty ? "none" : profile.injuries,
                "preferences": profile.preferences.isEmpty ? "none" : profile.preferences
            ]
        } else {
            result["profile"] = NSNull()
            result["warning"] = "No trainer profile set up yet."
        }

        // --- Recent workout logs ---
        let logs = await trainerStore.recentLogs(limit: 10)
        result["recent_workouts"] = logs.map { log in
            var d: [String: Any] = [
                "date": log.date,
                "title": log.workoutTitle,
                "type": log.workoutType.rawValue,
                "feedback": log.feedback.rawValue
            ]
            if let rpe = log.rpe              { d["rpe"] = rpe }
            if let mins = log.durationMinutes  { d["duration_minutes"] = mins }
            if !log.notes.isEmpty              { d["notes"] = log.notes }
            if let hrv = log.hrvAtLog          { d["hrv_at_workout"] = round(hrv * 10) / 10 }
            if let sleep = log.sleepHoursLastNight { d["sleep_last_night"] = round(sleep * 10) / 10 }
            if let tag = log.readinessTag      { d["readiness"] = tag }
            if let hr2min = log.postWorkoutHR2Min { d["post_workout_hr_2min"] = hr2min }
            if let loads = log.actualLoads { d["actual_loads"] = loads }
            if let sc = log.scaling { d["scaling"] = sc }
            return d
        }

        // --- Health snapshot from TrendStore ---
        let baselines = await trendStore.baselines
        let history = await trendStore.history
        let today = history.last  // most recent entry

        var healthSnapshot: [String: Any] = [
            "baseline_status": (await trendStore.baselineStatus).description
        ]
        if let hrv = today?.hrv            { healthSnapshot["current_hrv_ms"] = round(hrv * 10) / 10 }
        if let rhr = today?.restingHR      { healthSnapshot["resting_hr_bpm"] = round(rhr * 10) / 10 }
        if let sleep = today?.sleepHours   { healthSnapshot["sleep_hours_last_night"] = round(sleep * 10) / 10 }
        if let vo2 = today?.vo2Max         { healthSnapshot["vo2max_ml_kg_min"] = round(vo2 * 10) / 10 }
        if let cr = today?.cardioRecovery  { healthSnapshot["cardio_recovery_bpm_drop"] = round(cr * 10) / 10 }
        if let spo2 = today?.oxygenSaturation { healthSnapshot["spo2_pct"] = Int(spo2 * 100) }

        // Yesterday's activity (stored one day back)
        let sortedHistory = history.sorted { $0.date < $1.date }
        let yesterday = sortedHistory.count >= 2 ? sortedHistory[sortedHistory.count - 2] : nil
        if let steps = yesterday?.steps     { healthSnapshot["steps_yesterday"] = steps }
        if let cal = yesterday?.activeCalories { healthSnapshot["active_calories_yesterday"] = Int(cal) }
        if let exMins = yesterday?.exerciseMinutes { healthSnapshot["exercise_minutes_yesterday"] = Int(exMins) }

        if let avg7hrv = baselines.hrv7DayAvg   { healthSnapshot["hrv_7day_avg_ms"] = round(avg7hrv * 10) / 10 }
        if let avg30hrv = baselines.hrv30DayAvg { healthSnapshot["hrv_30day_avg_ms"] = round(avg30hrv * 10) / 10 }

        // Readiness tag
        if let hrv = today?.hrv, let avg30 = baselines.hrv30DayAvg, avg30 > 0 {
            let pct = (hrv - avg30) / avg30
            healthSnapshot["readiness_tag"] = pct >= -0.1 ? (pct >= 0.1 ? "high" : "medium") : "low"
        }

        result["health_snapshot"] = healthSnapshot

        // --- Uploaded reference program (capped at ~6000 chars to keep input tokens manageable) ---
        if let prog = await trainerStore.uploadedProgram, let name = await trainerStore.uploadedProgramName {
            let cap = 6000
            let truncated = prog.count > cap
            let content = truncated ? String(prog.prefix(cap)) + "\n\n[... truncated for brevity ...]" : prog
            result["uploaded_program"] = [
                "name": name,
                "content": content,
                "truncated": truncated
            ]
        }

        // --- Current plan summary ---
        if let plan = await trainerStore.currentPlan {
            let daysSummary = plan.days.map { day -> [String: Any] in
                if day.isRest {
                    return ["day_of_week": day.dayOfWeek, "type": "rest"]
                } else if let w = day.workout {
                    return [
                        "day_of_week": day.dayOfWeek,
                        "type": w.type.rawValue,
                        "title": w.title,
                        "estimated_minutes": w.estimatedMinutes
                    ]
                }
                return ["day_of_week": day.dayOfWeek, "type": "unscheduled"]
            }
            result["current_plan"] = [
                "week_start": plan.weekStartDate,
                "weekly_focus": plan.weeklyFocus,
                "days": daysSummary
            ]
        } else {
            result["current_plan"] = NSNull()
        }

        return encode(result)
    }

    // MARK: - write_training_plan

    private func writeTrainingPlan(input: [String: Any]) async -> String {
        guard let weeklyFocus = input["weekly_focus"] as? String,
              let coachNote = input["coach_note"] as? String,
              let daysRaw = input["days"] as? [[String: Any]] else {
            return encode(["error": "weekly_focus, coach_note, and days are required."])
        }

        let days = daysRaw.compactMap { parsePlannedDay($0) }
        guard !days.isEmpty else {
            return encode(["error": "No valid days could be parsed from the input."])
        }

        // Use Monday of the current week as the start date
        let weekStart = mondayOfCurrentWeek()
        let plan = WeeklyPlan(
            id: UUID().uuidString,
            weekStartDate: weekStart,
            generatedAt: Date(),
            weeklyFocus: weeklyFocus,
            coachNote: coachNote,
            days: days
        )

        do {
            try await trainerStore.savePlan(plan)
            return encode(["saved": true, "plan_id": plan.id, "days_scheduled": days.filter { !$0.isRest }.count])
        } catch {
            return encode(["saved": false, "error": error.localizedDescription])
        }
    }

    // MARK: - update_workout_days

    private func updateWorkoutDays(input: [String: Any]) async -> String {
        guard let reason = input["reason"] as? String,
              let daysRaw = input["days"] as? [[String: Any]] else {
            return encode(["error": "reason and days are required."])
        }

        guard var plan = await trainerStore.currentPlan else {
            return encode(["error": "No current plan exists. Use write_training_plan first."])
        }

        let updatedDays = daysRaw.compactMap { parsePlannedDay($0) }
        for updatedDay in updatedDays {
            if let idx = plan.days.firstIndex(where: { $0.dayOfWeek == updatedDay.dayOfWeek }) {
                plan.days[idx] = updatedDay
            }
        }

        do {
            // Save by directly replacing current plan without archiving
            try await trainerStore.savePlan(plan)
            return encode(["updated": true, "days_changed": updatedDays.count, "reason": reason])
        } catch {
            return encode(["updated": false, "error": error.localizedDescription])
        }
    }

    // MARK: - Parsing Helpers

    private func parsePlannedDay(_ raw: [String: Any]) -> PlannedDay? {
        guard let dow = raw["day_of_week"] as? Int,
              let isRest = raw["is_rest"] as? Bool else { return nil }

        var workout: PlannedWorkout? = nil
        if !isRest, let workoutRaw = raw["workout"] as? [String: Any] {
            workout = parsePlannedWorkout(workoutRaw)
        }

        return PlannedDay(dayOfWeek: dow, isRest: isRest, workout: workout)
    }

    private func parsePlannedWorkout(_ raw: [String: Any]) -> PlannedWorkout? {
        guard let title = raw["title"] as? String,
              let typeStr = raw["type"] as? String,
              let type = WorkoutType(rawValue: typeStr) else { return nil }

        let exercisesRaw = raw["exercises"] as? [[String: Any]] ?? []
        let exercises = exercisesRaw.map { parseExercise($0) }
        let estimatedMinutes = raw["estimated_minutes"] as? Int ?? 45

        return PlannedWorkout(
            id: UUID().uuidString,
            title: title,
            type: type,
            estimatedMinutes: estimatedMinutes,
            exercises: exercises,
            warmup: raw["warmup"] as? String,
            cooldown: raw["cooldown"] as? String,
            coachNote: raw["coach_note"] as? String ?? "",
            markdownContent: raw["markdown_content"] as? String
        )
    }

    private func parseExercise(_ raw: [String: Any]) -> ExerciseItem {
        ExerciseItem(
            id: UUID().uuidString,
            name: raw["name"] as? String ?? "Exercise",
            sets: raw["sets"] as? Int,
            reps: raw["reps"] as? String,
            duration: raw["duration"] as? String,
            rest: raw["rest"] as? String,
            weight: raw["weight"] as? String,
            notes: raw["notes"] as? String
        )
    }

    // MARK: - Helpers

    private func mondayOfCurrentWeek() -> String {
        let cal = Calendar.current
        let today = Date()
        let weekday = cal.component(.weekday, from: today)
        // weekday: 1=Sun, 2=Mon, ..., 7=Sat
        let daysToMonday = (weekday == 1) ? -6 : (2 - weekday)
        let monday = cal.date(byAdding: .day, value: daysToMonday, to: today) ?? today
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: monday)
    }

    private func encode(_ dict: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
