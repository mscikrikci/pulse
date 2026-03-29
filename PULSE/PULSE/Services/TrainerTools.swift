import Foundation

enum TrainerTools {

    static let definitions: [[String: Any]] = [

        // Tool 1: Full trainer context in one call
        [
            "name": "get_trainer_context",
            "description": "Returns everything needed to generate or update a training plan: the user's trainer profile (equipment, goals, fitness level, preferences), their last 10 workout logs with RPE and feedback, a snapshot of current health metrics from HealthKit (HRV, sleep, resting HR, VO2 max, cardio recovery, activity), and the current plan structure if one exists. Call this first in every trainer session.",
            "input_schema": [
                "type": "object",
                "properties": [:]
            ]
        ],

        // Tool 2: Write a full weekly training plan
        [
            "name": "write_training_plan",
            "description": "Saves a complete 7-day training plan. Call this to generate a new plan or replace the current one. Each day must be specified — either as a rest day or a workout. Workouts must be fully specified with exercises, sets, reps/duration, and a coach note explaining the rationale.",
            "input_schema": [
                "type": "object",
                "required": ["weekly_focus", "coach_note", "days"],
                "properties": [
                    "weekly_focus": [
                        "type": "string",
                        "description": "One sentence describing the overarching training focus for the week, e.g. 'Aerobic base building + upper body push volume'."
                    ],
                    "coach_note": [
                        "type": "string",
                        "description": "2–3 sentences explaining how this plan was shaped by the user's profile, health metrics, and recent workout feedback."
                    ],
                    "days": [
                        "type": "array",
                        "description": "Array of 7 day objects, one for each day Mon–Sun.",
                        "items": [
                            "type": "object",
                            "required": ["day_of_week", "is_rest"],
                            "properties": [
                                "day_of_week": [
                                    "type": "integer",
                                    "description": "1=Monday, 2=Tuesday, ..., 7=Sunday"
                                ],
                                "is_rest": [
                                    "type": "boolean"
                                ],
                                "workout": [
                                    "type": "object",
                                    "description": "Required when is_rest is false.",
                                    "properties": [
                                        "title": ["type": "string"],
                                        "type": [
                                            "type": "string",
                                            "enum": ["strength", "cardio", "hiit", "mobility", "recovery", "mixed"]
                                        ],
                                        "estimated_minutes": ["type": "integer"],
                                        "warmup": ["type": "string"],
                                        "cooldown": ["type": "string"],
                                        "coach_note": [
                                            "type": "string",
                                            "description": "1–2 sentences on why this workout fits today specifically (readiness, week position, goals)."
                                        ],
                                        "markdown_content": [
                                            "type": "string",
                                            "description": "Full workout written in Markdown. Use ## for sections (Warm-Up, Main Work, Cool-Down), **bold** for exercise names, and bullet lists for sets/reps/rest. Include coaching cues, form tips, and the coach note. This is the primary display format."
                                        ],
                                        "exercises": [
                                            "type": "array",
                                            "description": "Structured exercise list (used for logging and tracking). Mirror the markdown_content exercises here.",
                                            "items": [
                                                "type": "object",
                                                "required": ["name"],
                                                "properties": [
                                                    "name": ["type": "string"],
                                                    "sets": ["type": "integer"],
                                                    "reps": ["type": "string", "description": "e.g. '8–12', 'AMRAP', '20'"],
                                                    "duration": ["type": "string", "description": "e.g. '30 sec', '2 min'"],
                                                    "rest": ["type": "string", "description": "e.g. '60 sec'"],
                                                    "weight": ["type": "string", "description": "e.g. 'bodyweight', 'moderate load', 'RPE 7'"],
                                                    "notes": ["type": "string"]
                                                ]
                                            ]
                                        ]
                                    ]
                                ]
                            ]
                        ]
                    ]
                ]
            ]
        ],

        // Tool 3: Update specific days without regenerating the full plan
        [
            "name": "update_workout_days",
            "description": "Update one or more specific days in the current plan — use when adjusting upcoming workouts based on recent feedback or health changes without rebuilding the full week. Only pass the days you want to change.",
            "input_schema": [
                "type": "object",
                "required": ["reason", "days"],
                "properties": [
                    "reason": [
                        "type": "string",
                        "description": "Why these days are being updated, e.g. 'Low HRV today — replacing Thursday HIIT with mobility work'."
                    ],
                    "days": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "required": ["day_of_week", "is_rest"],
                            "properties": [
                                "day_of_week": ["type": "integer"],
                                "is_rest": ["type": "boolean"],
                                "workout": ["type": "object"]
                            ]
                        ]
                    ]
                ]
            ]
        ]
    ]
}
