import UserNotifications

struct NotificationScheduler {

    // MARK: - Authorization

    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
        return granted ?? false
    }

    // MARK: - Morning Readiness

    /// Schedules a daily morning notification at the given hour and minute.
    /// Default: 7:30am.
    static func scheduleMorningNotification(hour: Int = 7, minute: Int = 30) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["pulse.morning"])

        let content = UNMutableNotificationContent()
        content.title = "Good morning"
        content.body = "Your readiness summary is ready — tap to see today's report."
        content.sound = .default

        var components = DateComponents()
        components.hour = hour
        components.minute = minute

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "pulse.morning", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Weekly Coaching

    /// Schedules a Sunday 8am weekly coaching notification.
    static func scheduleWeeklyReview() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: ["pulse.weekly"])

        let content = UNMutableNotificationContent()
        content.title = "Weekly coaching"
        content.body = "Your week in review is ready — see what the data says."
        content.sound = .default

        var components = DateComponents()
        components.weekday = 1  // Sunday
        components.hour = 8
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
        let request = UNNotificationRequest(identifier: "pulse.weekly", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Activity Nudge

    /// Evaluates yesterday's activity against thresholds.
    /// Schedules a 5pm nudge if below threshold, cancels it if on target.
    static func evaluateAndScheduleActivityNudge(
        steps: Int?,
        activeCalories: Double?,
        stepsThreshold: Int = 4000,
        caloriesThreshold: Double = 300
    ) {
        let center = UNUserNotificationCenter.current()
        let stepsOk = (steps ?? 0) >= stepsThreshold
        let caloriesOk = (activeCalories ?? 0) >= caloriesThreshold

        if stepsOk && caloriesOk {
            center.removePendingNotificationRequests(withIdentifiers: ["pulse.activity"])
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: ["pulse.activity"])

        let content = UNMutableNotificationContent()
        content.title = "Activity check"
        content.body = nudgeBody(steps: steps, calories: activeCalories,
                                 stepsThreshold: stepsThreshold, caloriesThreshold: caloriesThreshold)
        content.sound = .default

        var components = DateComponents()
        components.hour = 17
        components.minute = 0

        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        let request = UNNotificationRequest(identifier: "pulse.activity", content: content, trigger: trigger)
        center.add(request)
    }

    // MARK: - Private

    private static func nudgeBody(
        steps: Int?,
        calories: Double?,
        stepsThreshold: Int,
        caloriesThreshold: Double
    ) -> String {
        if let s = steps, s < stepsThreshold {
            return "You're at \(s) steps today — a short walk now supports your recovery goals."
        }
        if let c = calories, c < caloriesThreshold {
            return "Active calories are low today — even light movement makes a difference."
        }
        return "A bit of movement this evening will support tomorrow's readiness."
    }
}
