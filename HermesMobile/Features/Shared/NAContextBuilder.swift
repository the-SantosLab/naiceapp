import Foundation
import SwiftData
import HealthKit

// MARK: - App Context Builder (Phase A)
@MainActor
struct NAContextBuilder {

    /// Builds a comprehensive context string from all local app data
    static func buildContext(
        moods: [MoodEntry],
        habits: [HabitLog],
        expenses: [Expense],
        health: HealthManager,
        calendar: CalendarManager,
        whoop: NAWhoop?
    ) -> String {
        let df = DateFormatter()
        df.dateStyle = .full
        df.timeStyle = .none
        let dateStr = df.string(from: Date())

        var parts: [String] = []
        parts.append("🔹 nAIce App Context — \(dateStr)")
        parts.append("")

        // Mood
        if let latest = moods.first {
            let moodName: String = {
                switch latest.mood {
                case "good": return "gut 😊"
                case "neutral": return "neutral 😐"
                case "bad": return "schlecht 😔"
                default: return latest.mood
                }
            }()
            parts.append("📊 Mood: \(moodName)")
            if !latest.note.isEmpty { parts.append("   Notiz: \(latest.note)") }
            let dayMoods = moods.filter { Calendar.current.isDateInToday($0.date) }
            parts.append("   Heute \(dayMoods.count) Einträge")
        } else {
            parts.append("📊 Mood: Keine Einträge heute")
        }
        parts.append("")

        // Habits
        let todayHabits = habits.filter { Calendar.current.isDateInToday($0.date) }
        if !todayHabits.isEmpty {
            parts.append("🎯 Gewohnheiten (\(todayHabits.count) heute geloggt):")
            for h in todayHabits {
                let name: String = {
                    switch h.habit {
                    case "walk": return "Spazieren"
                    case "water": return "Wasser"
                    case "reading": return "Lesen"
                    case "workout": return "Training"
                    case "meditation": return "Meditation"
                    default: return h.habit
                    }
                }()
                parts.append("   • \(name)")
            }
        } else {
            parts.append("🎯 Gewohnheiten: Heute noch nichts geloggt")
        }
        parts.append("")

        // HealthKit
        if health.isAuthorized {
            parts.append("❤️‍🔥 HealthKit (heute):")
            parts.append("   • Schritte: \(health.steps)")
            parts.append("   • Puls: \(Int(health.heartRate)) bpm")
            parts.append("   • HRV: \(Int(health.hrv)) ms")
            parts.append("   • Schlaf: \(String(format: "%.1f", health.sleepHours)) h")
        }
        parts.append("")

        // Whoop
        if let w = whoop, w.connected {
            parts.append("🟢 WHOOP:")
            parts.append("   • Recovery: \(w.recoveryScore)%")
            parts.append("   • HRV: \(Int(w.hrv)) ms")
            parts.append("   • Ruhepuls: \(w.restingHeartRate) bpm")
            parts.append("   • Strain: \(String(format: "%.1f", w.strain))")
            parts.append("   • Schlaf: \(String(format: "%.1f", w.sleepHours))h (Eff. \(Int(w.sleepEfficiency))%)")
            if w.phases.totalHours > 0 {
                parts.append("   • Schlaf-Phasen: Deep \(String(format: "%.1f", w.phases.deepHours))h, REM \(String(format: "%.1f", w.phases.remHours))h, Light \(String(format: "%.1f", w.phases.lightHours))h")
            }
            if !w.workouts.isEmpty {
                let totalStrain = w.workouts.reduce(0) { $0 + $1.strain }
                parts.append("   • \(w.workouts.count) Workouts (Strain: \(String(format: "%.1f", totalStrain)))")
                for wo in w.workouts.prefix(3) {
                    parts.append("     - \(wo.sport.capitalized): \(wo.durationMinutes)min, Strain \(String(format: "%.1f", wo.strain))")
                }
            }
        }
        parts.append("")

        // Calendar
        if calendar.isAuthorized {
            if calendar.todayEvents.isEmpty {
                parts.append("📅 Kalender: Keine Termine heute")
            } else {
                parts.append("📅 Kalender (\(calendar.todayEvents.count) Termine heute):")
                for event in calendar.todayEvents.prefix(5) {
                    let start = event.startDate.formatted(date: .omitted, time: .shortened)
                    parts.append("   • \(start) – \(event.title)")
                }
            }
        }
        parts.append("")

        // Expenses
        let thisMonth = expenses.filter { Calendar.current.isDate($0.date, equalTo: Date(), toGranularity: .month) }
        if !thisMonth.isEmpty {
            let total = thisMonth.reduce(0) { $0 + $1.amount }
            parts.append("💰 Finanzen (diesen Monat):")
            parts.append("   • Gesamt: \(Int(total)) €")
            let cats = Dictionary(grouping: thisMonth, by: { $0.category }).mapValues { $0.reduce(0) { $0 + $1.amount } }
            for (cat, amt) in cats.sorted(by: { $0.value > $1.value }).prefix(5) {
                parts.append("   • \(cat): \(Int(amt)) €")
            }
        }
        parts.append("")

        parts.append("Zeitstempel: \(ISO8601DateFormatter().string(from: Date()))")
        return parts.joined(separator: "\n")
    }
}