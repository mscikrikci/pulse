import Foundation

enum AgentTools {

    /// Full set used by Chat, Morning Card agent sessions.
    static let definitions: [[String: Any]] = [

        // Tool 1: Health data for a date or date range
        [
            "name": "get_health_data",
            "description": "Retrieve health metrics for a specific date or date range. Returns HRV, resting HR, sleep hours, sleep efficiency, respiratory rate, active calories, steps, alcohol reported, and subjective events logged. Use days_back for trend queries; use date for a single day.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "date": [
                        "type": "string",
                        "description": "ISO date (YYYY-MM-DD), or 'today', or 'yesterday'."
                    ],
                    "days_back": [
                        "type": "integer",
                        "description": "Number of days back from today. Max 90. Use for trend windows."
                    ]
                ]
            ]
        ],

        // Tool 2: Computed trend statistics
        [
            "name": "get_trend_stats",
            "description": "Compute a statistical summary for one metric over a time window. Returns mean, min, max, standard deviation, and trend direction (improving / declining / stable). Do not claim a metric is trending without calling this first.",
            "input_schema": [
                "type": "object",
                "required": ["metric", "days"],
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["hrv", "resting_hr", "respiratory_rate", "sleep_hours", "sleep_efficiency", "active_calories", "steps", "vo2max", "walking_speed", "walking_hr", "cardio_recovery", "stair_ascent_speed", "stair_descent_speed"]
                    ],
                    "days": [
                        "type": "integer",
                        "description": "Window size in days. Common: 7, 14, 30."
                    ]
                ]
            ]
        ],

        // Tool 3: Personal baseline values
        [
            "name": "get_baseline",
            "description": "Get the user's personal baseline values and baseline status (cold / building / established). Always call this before making comparisons — never assume what is normal for this person.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["all", "hrv", "resting_hr", "respiratory_rate", "sleep_hours", "sleep_efficiency",
                                 "vo2max", "walking_speed", "walking_hr"],
                        "description": "Omit or pass 'all' to get every baseline."
                    ]
                ]
            ]
        ],

        // Tool 4: Goal status and progress
        [
            "name": "get_goal_progress",
            "description": "Get goal definitions, targets, phase info, weekly snapshots, and pace assessment for active goals. Use when the user asks about goals or progress.",
            "input_schema": [
                "type": "object",
                "properties": [
                    "metric": [
                        "type": "string",
                        "enum": ["all", "hrv", "resting_hr", "respiratory_rate"],
                        "description": "Filter by metric, or 'all' for every goal."
                    ]
                ]
            ]
        ],

        // Tool 5: Protocol retrieval
        [
            "name": "get_protocols",
            "description": "Retrieve evidence-based Huberman Lab protocols for specific conditions. Returns protocol id (use this verbatim in your output), title, description, effort level, and duration. Use max_effort 'low' on low-readiness days.",
            "input_schema": [
                "type": "object",
                "required": ["conditions"],
                "properties": [
                    "conditions": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Condition flags: low_hrv, very_low_hrv, elevated_rhr, poor_sleep, elevated_respiratory_rate, high_stress, possible_illness, well_recovered, peak_readiness."
                    ],
                    "max_effort": [
                        "type": "string",
                        "enum": ["none", "low", "medium", "high"],
                        "description": "Filter to protocols at or below this effort level."
                    ]
                ]
            ]
        ],

        // Tool 6: Correlation between two metrics
        [
            "name": "get_correlation",
            "description": "Check whether two metrics show correlated patterns over a time window. Returns Pearson r, direction (positive / negative / none), and example data points. Use when investigating what might be driving changes in an outcome metric.",
            "input_schema": [
                "type": "object",
                "required": ["metric_a", "metric_b", "days"],
                "properties": [
                    "metric_a": [
                        "type": "string",
                        "enum": ["hrv", "resting_hr", "respiratory_rate", "sleep_hours", "sleep_efficiency", "active_calories", "steps", "vo2max", "walking_speed", "walking_hr", "cardio_recovery", "stair_ascent_speed", "stair_descent_speed"]
                    ],
                    "metric_b": [
                        "type": "string",
                        "enum": ["hrv", "resting_hr", "respiratory_rate", "sleep_hours", "sleep_efficiency", "active_calories", "steps", "vo2max", "walking_speed", "walking_hr", "cardio_recovery", "stair_ascent_speed", "stair_descent_speed"]
                    ],
                    "days": [
                        "type": "integer",
                        "description": "Lookback window. Min 5 days for meaningful correlation."
                    ]
                ]
            ]
        ],

        // Tool 7: Write a notable memory
        [
            "name": "write_memory",
            "description": "Store a notable observation, pattern, milestone, user statement, or anomaly in long-term memory for recall in future sessions. Use for: significant biometric events, correlations you have identified, things the user told you, goal milestones, unusual periods. Do NOT write trivial daily observations — only what would be genuinely useful to recall in 2–4 weeks.",
            "input_schema": [
                "type": "object",
                "required": ["type", "content", "tags", "importance"],
                "properties": [
                    "type": [
                        "type": "string",
                        "enum": ["observation", "pattern", "milestone", "user_statement", "anomaly"],
                        "description": "Category of memory."
                    ],
                    "content": [
                        "type": "string",
                        "description": "The memory content — 1–3 sentences. Be specific with numbers."
                    ],
                    "tags": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Relevant metric and context tags, e.g. [\"hrv\", \"stress\", \"travel\"]."
                    ],
                    "importance": [
                        "type": "string",
                        "enum": ["low", "medium", "high"],
                        "description": "High = critical event worth recalling for weeks. Low = mild observation."
                    ],
                    "source": [
                        "type": "string",
                        "description": "Feature that generated this memory: morning_card, chat, weekly_review."
                    ]
                ]
            ]
        ],

        // Tool 9: Add an action to today's task list
        [
            "name": "add_task",
            "description": "Add a concrete action to the user's Today's Actions list. Call this when you suggest a specific protocol or wellness action so the user can track and check it off. Only add the single most relevant action per response. The user will see it on the Today tab immediately.",
            "input_schema": [
                "type": "object",
                "required": ["title"],
                "properties": [
                    "title": [
                        "type": "string",
                        "description": "Human-readable action text, e.g. 'Do 10 min of physiological sighs before 2pm'. Be specific."
                    ],
                    "protocol_id": [
                        "type": "string",
                        "description": "Optional: exact protocol id from the corpus if this action maps to a protocol."
                    ]
                ]
            ]
        ],

        // Tool 8: Rewrite the user identity summary (weekly review only)
        [
            "name": "write_identity_summary",
            "description": "Rewrite the compressed user model that is injected into every future session. Call this at the end of the weekly review to update the model with this week's observations. Write in third person. 3–5 sentences covering: active health focus, key sensitivities, key strengths, current trajectory.",
            "input_schema": [
                "type": "object",
                "required": ["summary", "key_sensitivities", "key_strengths", "active_focus"],
                "properties": [
                    "summary": [
                        "type": "string",
                        "description": "3–5 sentence compressed description of who this person is as a health subject."
                    ],
                    "key_sensitivities": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Known negative drivers, e.g. [\"alcohol → HRV\", \"work_stress → HRV\"]."
                    ],
                    "key_strengths": [
                        "type": "array",
                        "items": ["type": "string"],
                        "description": "Consistent positive behaviors, e.g. [\"sleep_consistency\", \"morning_routine\"]."
                    ],
                    "active_focus": [
                        "type": "string",
                        "description": "Current priority, e.g. \"Phase 2 (Build) — introducing Zone 2 cardio 2-3x/week\"."
                    ]
                ]
            ]
        ]
    ]
}

// MARK: - Helpers

extension Dictionary where Key == String, Value == Any {
    /// Serializes the dictionary to a compact JSON string for logging.
    var jsonString: String {
        guard let data = try? JSONSerialization.data(withJSONObject: self),
              let str = String(data: data, encoding: .utf8) else { return "{}" }
        return str
    }
}
