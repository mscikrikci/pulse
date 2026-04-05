import Foundation

// MARK: - Profile

struct TrainerProfile: Codable, Sendable {
    var fitnessLevel: FitnessLevel
    var goals: [TrainingGoal]
    var equipment: [Equipment]
    var daysPerWeek: Int              // 2–6
    var sessionMinutes: Int           // 20, 30, 45, 60, 90
    var injuries: String              // free-text limitations
    var preferences: String           // free-text preferences
    var createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case fitnessLevel = "fitness_level"
        case goals, equipment
        case daysPerWeek = "days_per_week"
        case sessionMinutes = "session_minutes"
        case injuries, preferences
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum FitnessLevel: String, Codable, Sendable, CaseIterable {
    case beginner     = "beginner"
    case intermediate = "intermediate"
    case advanced     = "advanced"

    var label: String {
        switch self {
        case .beginner:     return "Beginner"
        case .intermediate: return "Intermediate"
        case .advanced:     return "Advanced"
        }
    }

    var description: String {
        switch self {
        case .beginner:     return "New to structured training or returning after a long break"
        case .intermediate: return "Training consistently for 6+ months"
        case .advanced:     return "3+ years of structured training"
        }
    }
}

enum TrainingGoal: String, Codable, Sendable, CaseIterable {
    case buildStrength       = "build_strength"
    case buildMuscle         = "build_muscle"
    case fatLoss             = "fat_loss"
    case improveCardio       = "improve_cardio"
    case improveMobility     = "improve_mobility"
    case generalFitness      = "general_fitness"
    case athleticPerformance = "athletic_performance"
    case stressRelief        = "stress_relief"

    var label: String {
        switch self {
        case .buildStrength:       return "Build Strength"
        case .buildMuscle:         return "Build Muscle"
        case .fatLoss:             return "Fat Loss"
        case .improveCardio:       return "Improve Cardio"
        case .improveMobility:     return "Mobility & Flexibility"
        case .generalFitness:      return "General Fitness"
        case .athleticPerformance: return "Athletic Performance"
        case .stressRelief:        return "Stress Relief"
        }
    }

    var icon: String {
        switch self {
        case .buildStrength:       return "dumbbell.fill"
        case .buildMuscle:         return "figure.strengthtraining.traditional"
        case .fatLoss:             return "flame.fill"
        case .improveCardio:       return "figure.run"
        case .improveMobility:     return "figure.flexibility"
        case .generalFitness:      return "figure.mixed.cardio"
        case .athleticPerformance: return "bolt.fill"
        case .stressRelief:        return "brain.head.profile"
        }
    }
}

enum Equipment: String, Codable, Sendable, CaseIterable {
    case bodyweight      = "bodyweight"
    case dumbbells       = "dumbbells"
    case barbell         = "barbell"
    case pullUpBar       = "pull_up_bar"
    case resistanceBands = "resistance_bands"
    case kettlebell      = "kettlebell"
    case bench           = "bench"
    case cableMachine    = "cable_machine"
    case fullGym         = "full_gym"
    case jumpRope        = "jump_rope"
    case yogaMat         = "yoga_mat"
    case trx             = "trx"

    var label: String {
        switch self {
        case .bodyweight:      return "Bodyweight"
        case .dumbbells:       return "Dumbbells"
        case .barbell:         return "Barbell"
        case .pullUpBar:       return "Pull-Up Bar"
        case .resistanceBands: return "Resistance Bands"
        case .kettlebell:      return "Kettlebell"
        case .bench:           return "Bench"
        case .cableMachine:    return "Cable Machine"
        case .fullGym:         return "Full Gym"
        case .jumpRope:        return "Jump Rope"
        case .yogaMat:         return "Yoga Mat"
        case .trx:             return "TRX / Suspension"
        }
    }

    var icon: String {
        switch self {
        case .bodyweight:      return "figure.stand"
        case .dumbbells:       return "dumbbell.fill"
        case .barbell:         return "dumbbell.fill"
        case .pullUpBar:       return "figure.pull.up"
        case .resistanceBands: return "arrow.left.and.right"
        case .kettlebell:      return "dumbbell"
        case .bench:           return "rectangle.fill"
        case .cableMachine:    return "cable.connector.horizontal"
        case .fullGym:         return "building.2.fill"
        case .jumpRope:        return "figure.jump.rope"
        case .yogaMat:         return "rectangle.portrait.fill"
        case .trx:             return "figure.gymnastics"
        }
    }
}

// MARK: - Training Plan

struct WeeklyPlan: Codable, Sendable, Identifiable {
    var id: String
    var weekStartDate: String       // "YYYY-MM-DD" — Monday of the week
    var generatedAt: Date
    var weeklyFocus: String         // e.g. "Aerobic base + upper body volume"
    var coachNote: String           // why this plan was shaped this way
    var days: [PlannedDay]          // always 7, indexed 0=Mon...6=Sun

    enum CodingKeys: String, CodingKey {
        case id
        case weekStartDate = "week_start_date"
        case generatedAt   = "generated_at"
        case weeklyFocus   = "weekly_focus"
        case coachNote     = "coach_note"
        case days
    }
}

struct PlannedDay: Codable, Sendable {
    var dayOfWeek: Int              // 1=Mon...7=Sun
    var isRest: Bool
    var workout: PlannedWorkout?

    enum CodingKeys: String, CodingKey {
        case dayOfWeek = "day_of_week"
        case isRest    = "is_rest"
        case workout
    }
}

struct PlannedWorkout: Codable, Sendable, Identifiable {
    var id: String
    var title: String
    var type: WorkoutType
    var estimatedMinutes: Int
    var exercises: [ExerciseItem]
    var warmup: String?
    var cooldown: String?
    var coachNote: String           // why this workout was chosen for this day
    /// Full Markdown-formatted workout — displayed in WorkoutDetailView.
    /// Written by the AI; overrides the exercises array for display purposes.
    var markdownContent: String?

    enum CodingKeys: String, CodingKey {
        case id, title, type
        case estimatedMinutes = "estimated_minutes"
        case exercises, warmup, cooldown
        case coachNote = "coach_note"
        case markdownContent = "markdown_content"
    }
}

enum WorkoutType: String, Codable, Sendable, CaseIterable {
    case strength   = "strength"
    case cardio     = "cardio"
    case hiit       = "hiit"
    case mobility   = "mobility"
    case recovery   = "recovery"
    case mixed      = "mixed"

    var label: String {
        switch self {
        case .strength:  return "Strength"
        case .cardio:    return "Cardio"
        case .hiit:      return "HIIT"
        case .mobility:  return "Mobility"
        case .recovery:  return "Recovery"
        case .mixed:     return "Mixed"
        }
    }

    var icon: String {
        switch self {
        case .strength:  return "dumbbell.fill"
        case .cardio:    return "figure.run"
        case .hiit:      return "bolt.fill"
        case .mobility:  return "figure.flexibility"
        case .recovery:  return "leaf.fill"
        case .mixed:     return "figure.mixed.cardio"
        }
    }

    var color: String {   // use with Color(named:) or map in view
        switch self {
        case .strength:  return "blue"
        case .cardio:    return "orange"
        case .hiit:      return "red"
        case .mobility:  return "green"
        case .recovery:  return "teal"
        case .mixed:     return "purple"
        }
    }
}

struct ExerciseItem: Codable, Sendable, Identifiable {
    var id: String
    var name: String
    var sets: Int?
    var reps: String?       // "8–12", "AMRAP", "15"
    var duration: String?   // "30 sec", "2 min"
    var rest: String?       // "60 sec", "2 min"
    var weight: String?     // "bodyweight", "moderate", "heavy", "RPE 7"
    var notes: String?
}

// MARK: - Workout Log

struct WorkoutLog: Codable, Sendable, Identifiable {
    var id: String
    var date: String                    // "YYYY-MM-DD"
    var workoutId: String
    var workoutTitle: String
    var workoutType: WorkoutType
    var completedAt: Date
    var durationMinutes: Int?
    var rpe: Int?                       // 1–10
    var feedback: WorkoutFeedback
    var notes: String
    // Health context at time of workout
    var hrvAtLog: Double?
    var sleepHoursLastNight: Double?
    var readinessTag: String?           // "high" | "medium" | "low"
    var postWorkoutHR2Min: Int?        // BPM at 2 minutes post-workout — key recovery signal
    var actualLoads: String?           // e.g. "DL: 100kg, BSS: 12.5kg DB — grip limited heavier"
    var scaling: String?               // what was scaled and why

    enum CodingKeys: String, CodingKey {
        case id, date
        case workoutId    = "workout_id"
        case workoutTitle = "workout_title"
        case workoutType  = "workout_type"
        case completedAt  = "completed_at"
        case durationMinutes = "duration_minutes"
        case rpe, feedback, notes
        case hrvAtLog          = "hrv_at_log"
        case sleepHoursLastNight = "sleep_hours_last_night"
        case readinessTag      = "readiness_tag"
        case postWorkoutHR2Min = "post_workout_hr_2min"
        case actualLoads = "actual_loads"
        case scaling
    }
}

enum WorkoutFeedback: String, Codable, Sendable, CaseIterable {
    case tooEasy   = "too_easy"
    case justRight = "just_right"
    case tooHard   = "too_hard"
    case skipped   = "skipped"

    var label: String {
        switch self {
        case .tooEasy:   return "Too Easy"
        case .justRight: return "Just Right"
        case .tooHard:   return "Too Hard"
        case .skipped:   return "Skipped"
        }
    }

    var icon: String {
        switch self {
        case .tooEasy:   return "arrow.up.circle"
        case .justRight: return "checkmark.circle.fill"
        case .tooHard:   return "exclamationmark.circle"
        case .skipped:   return "xmark.circle"
        }
    }
}

// MARK: - Store Data

struct TrainerStoreData: Codable, Sendable {
    var profile: TrainerProfile?
    var currentPlan: WeeklyPlan?
    var planHistory: [WeeklyPlan]       // last 4 weeks
    var workoutLogs: [WorkoutLog]       // last 90 days
    var uploadedProgram: String?       // raw text of an uploaded training program
    var uploadedProgramName: String?   // filename for display

    enum CodingKeys: String, CodingKey {
        case profile
        case currentPlan  = "current_plan"
        case planHistory  = "plan_history"
        case workoutLogs  = "workout_logs"
        case uploadedProgram = "uploaded_program"
        case uploadedProgramName = "uploaded_program_name"
    }

    static func empty() -> TrainerStoreData {
        TrainerStoreData(profile: nil, currentPlan: nil, planHistory: [], workoutLogs: [])
    }
}
