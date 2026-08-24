import Foundation

// MARK: - Rollup Models (console.naice.app/api/v2/rollup)

struct NARollup: Codable {
    let ts: String
    let date: String
    let whoop: NAWhoopRollup?
    let calendar: NACalendarRollup?
    let journal: NAJournalRollup?
    let business: NABusinessRollup?
    let tasks: NATasksRollup?
    let deals: NADealsRollup?
    let summary: NASummary?
}

struct NAWhoopRollup: Codable {
    let recovery: NAWhoopRecovery?
    let sleep: NAWhoopSleep?
    let cycle: NAWhoopCycle?
    let trends_7d: NAWhoopTrends?
    let workouts: [NAWhoopWorkout]?
}

struct NAWhoopRecovery: Codable {
    let score: Int
    let hrv: Int
    let rhr: Int
    let spo2: Double?
    let skin_temp: Double?
    let synced_at: String?
}

struct NAWhoopSleep: Codable {
    let performance_pct: Int?
    let efficiency_pct: Double?
    let net_hours: Double
    let net_minutes: Int
    let deep_minutes: Int
    let rem_minutes: Int
    let light_minutes: Int
    let awake_minutes: Int
    let respiratory_rate: Double?
    let start: String?
    let end: String?
}

struct NAWhoopCycle: Codable {
    let strain: Double?
    let kilojoule: Double?
    let avg_hr: Int?
    let max_hr: Int?
}

struct NAWhoopTrends: Codable {
    let avg_recovery: Int?
    let avg_hrv: Int?
    let avg_sleep_hours: Double?
    let avg_strain: Double?
}

struct NAWhoopWorkout: Codable {
    let sport: String
    let strain: Double
    let max_hr: Int?
    let avg_hr: Int?
    let kilojoule: Double?
    let start: String?
    let end: String?
}

struct NACalendarRollup: Codable {
    let events: [NACalendarEvent]?
    let count: Int
}

struct NACalendarEvent: Codable {
    let title: String
    let start: String?
    let end: String?
    let location: String?
}

struct NAJournalRollup: Codable {
    let entries: [NAJournalEntry]?
    let count: Int
    let this_week: Int?
}

struct NAJournalEntry: Codable {
    let id: String
    let text: String
    let created_at: String?
}

struct NABusinessRollup: Codable {
    let foodloop: NABusinessProject?
    let naice: NABusinessProject?
    let schaffer: NABusinessProject?
    let parcelmate: NABusinessProject?
}

struct NABusinessProject: Codable {
    let total: Int
    let statuses: [String: Int]?
    let hot: Int?
    let emails: [String: Int]?
}

struct NATasksRollup: Codable {
    let total: Int
    let active: Int
    let tasks: [NATask]?
}

struct NATask: Codable, Identifiable {
    let id: String
    let title: String
    let priority: String?
    let deadline: String?
    let source: String?
    let project: String?
    let status: String?
    let created: String?
}

struct NADealsRollup: Codable {
    let active_deals: Int
    let total_value_eur: Int
    let deals: [NADeal]?
}

struct NADeal: Codable, Identifiable {
    var id: String { name }
    let name: String
    let value: Int
    let status: String?
}

struct NASummary: Codable {
    let recovery: Int?
    let hrv: Int?
    let sleep_hours: Double?
    let sleep_pct: Int?
    let strain: Double?
    let naice_total: Int?
    let naice_pitched_today: Int?
    let events_today: Int?
    let journal_entries_today: Int?
    let flags: [NASummaryFlag]?
}

struct NASummaryFlag: Codable, Identifiable {
    var id: String { text }
    let level: String   // "yellow", "red", "green"
    let text: String
}