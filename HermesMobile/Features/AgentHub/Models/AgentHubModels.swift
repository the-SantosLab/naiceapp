import Foundation

// MARK: - Workout Model
struct NAWorkout: Identifiable {
    let id = UUID()
    let sport: String
    let strain: Double
    let maxHr: Int
    let avgHr: Int
    let kilojoule: Double
    let start: String?
    let end: String?

    var durationMinutes: Int {
        guard let s = start, let e = end else { return 0 }
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let sd = df.date(from: s) ?? { df.formatOptions = [.withInternetDateTime]; return df.date(from: s) }(),
              let ed = df.date(from: e) ?? { df.formatOptions = [.withInternetDateTime]; return df.date(from: e) }()
        else { return 0 }
        return Int(ed.timeIntervalSince(sd) / 60)
    }

    var sportIcon: String {
        switch sport {
        case "walking": return "figure.walk"
        case "running": return "figure.run"
        case "cycling": return "bicycle"
        case "swimming": return "figure.pool.swim"
        case "yoga": return "figure.cooldown"
        case "meditation": return "brain.head.profile"
        default: return "heart.circle"
        }
    }

    static func from(_ d: [String: Any]) -> NAWorkout {
        NAWorkout(
            sport: d["sport"] as? String ?? "",
            strain: d["strain"] as? Double ?? 0,
            maxHr: d["max_hr"] as? Int ?? 0,
            avgHr: d["avg_hr"] as? Int ?? 0,
            kilojoule: d["kilojoule"] as? Double ?? 0,
            start: d["start"] as? String,
            end: d["end"] as? String
        )
    }
}

// MARK: - Sleep Phases Model
struct NASleepPhases {
    let deepHours: Double
    let remHours: Double
    let lightHours: Double
    let awakeHours: Double
    let efficiencyPct: Double
    let totalHours: Double

    static func from(_ d: [String: Any]) -> NASleepPhases {
        NASleepPhases(
            deepHours: d["deep_hours"] as? Double ?? 0,
            remHours: d["rem_hours"] as? Double ?? 0,
            lightHours: d["light_hours"] as? Double ?? 0,
            awakeHours: d["awake_hours"] as? Double ?? 0,
            efficiencyPct: d["efficiency_pct"] as? Double ?? 0,
            totalHours: d["total_hours"] as? Double ?? 0
        )
    }
}

// MARK: - Whoop Summary Model
struct NAWhoop {
    let connected: Bool
    let recoveryScore: Int
    let restingHeartRate: Int
    let hrv: Double
    let spo2: Double
    let skinTemp: Double
    let recoverySyncedAt: String
    let sleepHours: Double
    let sleepEfficiency: Double
    let sleepPerformance: Double
    let respiratoryRate: Double
    let sleepStart: String?
    let sleepEnd: String?
    let phases: NASleepPhases
    let phases7day: NASleepPhases?
    let strain: Double
    let kilojoule: Double
    let avgHeartRate: Int
    let maxHeartRate: Int
    let cycleStart: String?
    let cycleEnd: String?
    let workouts: [NAWorkout]

    var lastSyncRelative: String {
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let d = df.date(from: recoverySyncedAt) else {
            df.formatOptions = [.withInternetDateTime]
            guard let d = df.date(from: recoverySyncedAt) else { return recoverySyncedAt }
            let diff = Int(-d.timeIntervalSinceNow)
            return diff < 60 ? "vor \(diff)s" : diff < 3600 ? "vor \(diff/60)m" :
                   diff < 86400 ? "vor \(diff/3600)h" : "vor \(diff/86400)d"
        }
        let diff = Int(-d.timeIntervalSinceNow)
        return diff < 60 ? "vor \(diff)s" : diff < 3600 ? "vor \(diff/60)m" :
               diff < 86400 ? "vor \(diff/3600)h" : "vor \(diff/86400)d"
    }

    static func from(_ d: [String: Any]) -> NAWhoop {
        let r = d["recovery"] as? [String: Any] ?? [:]
        let s = d["sleep"] as? [String: Any] ?? [:]
        let p = s["phases"] as? [String: Any] ?? [:]
        let p7 = s["phases_7day"] as? [String: Any]
        let c = d["cycle"] as? [String: Any] ?? [:]
        let ws = (d["workouts"] as? [[String: Any]] ?? []).map { NAWorkout.from($0) }
        return NAWhoop(
            connected: d["connected"] as? Bool ?? false,
            recoveryScore: r["score"] as? Int ?? 0,
            restingHeartRate: r["resting_heart_rate"] as? Int ?? 0,
            hrv: r["hrv"] as? Double ?? 0,
            spo2: r["spo2"] as? Double ?? 0,
            skinTemp: r["skin_temp"] as? Double ?? 0,
            recoverySyncedAt: r["synced_at"] as? String ?? "",
            sleepHours: s["total_hours"] as? Double ?? 0,
            sleepEfficiency: s["efficiency_pct"] as? Double ?? 0,
            sleepPerformance: s["performance_pct"] as? Double ?? 0,
            respiratoryRate: s["respiratory_rate"] as? Double ?? 0,
            sleepStart: s["start"] as? String,
            sleepEnd: s["end"] as? String,
            phases: NASleepPhases.from(p),
            phases7day: p7.map { NASleepPhases.from($0) },
            strain: c["strain"] as? Double ?? 0,
            kilojoule: c["kilojoule"] as? Double ?? 0,
            avgHeartRate: c["avg_hr"] as? Int ?? 0,
            maxHeartRate: c["max_hr"] as? Int ?? 0,
            cycleStart: c["start"] as? String,
            cycleEnd: c["end"] as? String,
            workouts: ws
        )
    }
}

// MARK: - Idea Model
struct NAIdea: Identifiable {
    let id: String
    let text: String
    let createdAt: Date

    static func from(_ d: [String: Any]) -> NAIdea? {
        guard let id = d["id"] as? String, let text = d["text"] as? String else { return nil }
        let dateStr = d["created_at"] as? String ?? ""
        let df = ISO8601DateFormatter()
        df.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let date = df.date(from: dateStr) ?? ISO8601DateFormatter().date(from: dateStr.components(separatedBy: ".").first ?? "") ?? Date()
        return NAIdea(id: id, text: text, createdAt: date)
    }
}