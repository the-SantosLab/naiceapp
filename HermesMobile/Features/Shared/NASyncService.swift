import Foundation
import SwiftData
import HealthKit

// MARK: - Sync Service (Phase B)
@MainActor
class NASyncService: ObservableObject {
    static let shared = NASyncService()

    private let syncURL = URL(string: "https://health.santoslab.de/api/naice/sync")!
    private var lastSync: Date?

    /// Aggregate all local data and send to backend
    func syncAll(
        moods: [MoodEntry],
        habits: [HabitLog],
        expenses: [Expense],
        health: HealthManager,
        whoop: NAWhoop?
    ) async {
        let payload = buildPayload(moods: moods, habits: habits, expenses: expenses, health: health, whoop: whoop)

        var req = URLRequest(url: syncURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: payload, options: [.fragmentsAllowed])

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let httpResp = resp as? HTTPURLResponse,
              httpResp.statusCode == 200
        else { return }

        lastSync = Date()
        if let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let msg = dict["message"] as? String {
            print("[NASync] \(msg)")
        }
    }

    private func buildPayload(
        moods: [MoodEntry],
        habits: [HabitLog],
        expenses: [Expense],
        health: HealthManager,
        whoop: NAWhoop?
    ) -> [String: Any] {
        let df = ISO8601DateFormatter()

        // Moods (today + last 7 days aggregated)
        let todayMoods = moods.filter { Calendar.current.isDateInToday($0.date) }
        let weekMoods = moods.filter { $0.date >= Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date() }

        // Habits (today)
        let todayHabits = habits.filter { Calendar.current.isDateInToday($0.date) }

        // Expenses (this month)
        let thisMonth = expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }

        // HealthKit (today, aggregated)
        var healthPayload: [String: Any] = [:]
        if health.isAuthorized {
            healthPayload = [
                "steps": health.steps,
                "heart_rate": Int(health.heartRate),
                "hrv": Int(health.hrv),
                "sleep_hours": health.sleepHours
            ]
        }

        // Whoop reference
        var whoopPayload: [String: Any] = [:]
        if let w = whoop, w.connected {
            whoopPayload = [
                "recovery_score": w.recoveryScore,
                "hrv": Int(w.hrv),
                "resting_hr": w.restingHeartRate,
                "strain": w.strain,
                "sleep_hours": w.sleepHours,
                "sleep_efficiency": Int(w.sleepEfficiency)
            ]
            if !w.workouts.isEmpty {
                whoopPayload["workout_count"] = w.workouts.count
                whoopPayload["total_strain"] = w.workouts.reduce(0) { $0 + $1.strain }
            }
        }

        // Mood summary
        var moodSummary: [String: Any] = [:]
        let goodCount = weekMoods.filter { $0.mood == "good" }.count
        let neutralCount = weekMoods.filter { $0.mood == "neutral" }.count
        let badCount = weekMoods.filter { $0.mood == "bad" }.count
        moodSummary = [
            "today_count": todayMoods.count,
            "week_good": goodCount,
            "week_neutral": neutralCount,
            "week_bad": badCount,
            "latest_mood": moods.first?.mood ?? ""
        ]

        // Habit summary
        var habitSummary: [String: Any] = [:]
        let todayHabitNames = todayHabits.map { $0.habit }
        habitSummary = [
            "today_count": todayHabits.count,
            "today_habits": todayHabitNames
        ]

        // Expense summary
        var expensePayload: [String: Any] = [:]
        if !thisMonth.isEmpty {
            let total = thisMonth.reduce(0) { $0 + $1.amount }
            let cats = Dictionary(grouping: thisMonth, by: { $0.category }).mapValues { $0.reduce(0) { $0 + $1.amount } }
            expensePayload = [
                "monthly_total": Int(total),
                "categories": cats.mapValues { Int($0) }
            ]
        }

        let payload: [String: Any] = [
            "synced_at": df.string(from: Date()),
            "device": "ios",
            "mood": moodSummary,
            "habits": habitSummary,
            "healthkit": healthPayload,
            "whoop": whoopPayload,
            "expenses": expensePayload,
            "calendar_events_today": CalendarManager.shared.todayEvents.count
        ]

        return payload
    }

    var timeSinceLastSync: String {
        guard let last = lastSync else { return "nie" }
        let diff = Int(-last.timeIntervalSinceNow)
        if diff < 60 { return "vor \(diff)s" }
        if diff < 3600 { return "vor \(diff/60)m" }
        return "vor \(diff/3600)h"
    }
}