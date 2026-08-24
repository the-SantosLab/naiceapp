import Foundation

// MARK: - WhatsApp Models

struct WAStatus: Codable {
    let sessions: [String]
    let log_dir: String?
    let reminder_window_h: Int?
}

struct WAPendingResponse: Codable {
    let business: [String: WAPendingChat]
    let privat: [String: WAPendingChat]
}

struct WAPendingChat: Codable, Identifiable {
    var id: String { remoteJid ?? UUID().uuidString }
    let remoteJid: String?
    let contact: String
    let lastIncomingTs: Int64
    let lastIncomingText: String?
    let replied: Bool
    let lastReminderTs: Int64?

    var lastIncomingDate: Date {
        Date(timeIntervalSince1970: TimeInterval(lastIncomingTs) / 1000.0)
    }

    var timeAgo: String {
        let elapsed = Date().timeIntervalSince(lastIncomingDate)
        if elapsed < 60 { return "gerade" }
        if elapsed < 3600 { return "vor \(Int(elapsed / 60)) min" }
        if elapsed < 86400 { return "vor \(Int(elapsed / 3600)) h" }
        let days = Int(elapsed / 86400)
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }

    var urgency: WAMessageUrgency {
        let elapsed = Date().timeIntervalSince(lastIncomingDate)
        if elapsed > 43200 { return .red }      // >12h
        if elapsed > 21600 { return .yellow }    // >6h
        return .none
    }

    enum WAMessageUrgency {
        case red, yellow, none
    }
}

struct WAMessagesResponse: Codable {
    let messages: [WAMessage]
}

struct WAMessage: Codable, Identifiable {
    var id: String { "\(ts)-\(from)" }
    let ts: Int64
    let from: String
    let sender: String?
    let text: String
    let outgoing: Bool

    var date: Date {
        Date(timeIntervalSince1970: TimeInterval(ts) / 1000.0)
    }

    var formattedTime: String {
        let f = DateFormatter()
        f.dateFormat = "dd.MM. HH:mm"
        return f.string(from: date)
    }
}

// MARK: - Combined session chat list
struct WAChatItem: Identifiable, Hashable {
    var id: String { remoteJid }
    let remoteJid: String
    let contact: String
    let lastIncomingTs: Int64
    let lastIncomingText: String?
    let replied: Bool
    let session: String // "business" or "privat"

    var lastIncomingDate: Date {
        Date(timeIntervalSince1970: TimeInterval(lastIncomingTs) / 1000.0)
    }

    var timeAgo: String {
        let elapsed = Date().timeIntervalSince(lastIncomingDate)
        if elapsed < 60 { return "gerade" }
        if elapsed < 3600 { return "vor \(Int(elapsed / 60)) min" }
        if elapsed < 86400 { return "vor \(Int(elapsed / 3600)) h" }
        let days = Int(elapsed / 86400)
        return days == 1 ? "vor 1 Tag" : "vor \(days) Tagen"
    }

    var urgency: WAPendingChat.WAMessageUrgency {
        let elapsed = Date().timeIntervalSince(lastIncomingDate)
        if elapsed > 43200 { return .red }
        if elapsed > 21600 { return .yellow }
        return .none
    }
}

// MARK: - Tab badge data
struct WABadgeData {
    let businessUnread: Int
    let privatUnread: Int
    var totalUnread: Int { businessUnread + privatUnread }
}