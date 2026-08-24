import Foundation
import SwiftUI

// MARK: - WhatsApp ViewModel
@MainActor
class WhatsAppViewModel: ObservableObject {
    static let shared = WhatsAppViewModel()

    private let baseURL = URL(string: "https://health.santoslab.de/api/whatsapp")!
    private let iso8601: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    @Published var pendingBusiness: [WAPendingChat] = []
    @Published var pendingPrivat: [WAPendingChat] = []
    @Published var messages: [String: [WAMessage]] = [:] // session + remoteJid -> messages
    @Published var isLoading = false
    @Published var lastError: String? = nil
    @Published var sessions: [String] = []

    private var timer: Timer?

    var totalUnread: Int {
        (pendingBusiness.filter { !$0.replied }.count) + (pendingPrivat.filter { !$0.replied }.count)
    }

    var businessUnread: Int {
        pendingBusiness.filter { !$0.replied }.count
    }

    var privatUnread: Int {
        pendingPrivat.filter { !$0.replied }.count
    }

    // Build flat list of all unreplied chats
    var unrepliedChats: [WAChatItem] {
        var items: [WAChatItem] = []
        for (key, chats) in [("business", pendingBusiness), ("privat", pendingPrivat)] {
            for chat in chats where !chat.replied {
                items.append(WAChatItem(
                    remoteJid: chat.remoteJid ?? chat.id,
                    contact: chat.contact,
                    lastIncomingTs: chat.lastIncomingTs,
                    lastIncomingText: chat.lastIncomingText,
                    replied: chat.replied,
                    session: key
                ))
            }
        }
        return items.sorted { $0.lastIncomingTs < $1.lastIncomingTs }
    }

    var allDone: Bool {
        unrepliedChats.isEmpty
    }

    // MARK: - API Calls
    func fetchStatus() async {
        guard let url = URL(string: "\(baseURL)/status") else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            let status = try JSONDecoder().decode(WAStatus.self, from: data)
            sessions = status.sessions
        } catch {
            // Non-critical, don't show error
        }
    }

    func fetchPending() async {
        guard let url = URL(string: "\(baseURL)/pending") else { return }
        isLoading = true
        lastError = nil

        var req = URLRequest(url: url)
        req.timeoutInterval = 10

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse else {
                lastError = "Keine HTTP-Response"
                isLoading = false
                return
            }
            guard http.statusCode == 200 else {
                lastError = "HTTP \(http.statusCode)"
                isLoading = false
                return
            }
            let decoded = try JSONDecoder().decode(WAPendingResponse.self, from: data)
            pendingBusiness = Array(decoded.business.values)
            pendingPrivat = Array(decoded.privat.values)
            isLoading = false
        } catch {
            lastError = error.localizedDescription
            isLoading = false
        }
    }

    func fetchMessages(session: String, for remoteJid: String) async {
        guard var components = URLComponents(string: "\(baseURL)/messages") else { return }
        components.queryItems = [URLQueryItem(name: "session", value: session)]

        guard let url = components.url else { return }
        var req = URLRequest(url: url)
        req.timeoutInterval = 10

        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }

            // The response is a JSON object with a "messages" array
            let decoded = try JSONDecoder().decode(WAMessagesResponse.self, from: data)

            // Filter messages for this contact
            let contactMessages = decoded.messages.filter { $0.from == remoteJid || $0.from == remoteJid }
            messages[remoteJid] = contactMessages

            // Also store under session key
            let key = "\(session):\(remoteJid)"
            messages[key] = contactMessages.suffix(20)
        } catch {
            // Silently fail for messages
        }
    }

    func getMessages(session: String, remoteJid: String) -> [WAMessage] {
        let key = "\(session):\(remoteJid)"
        return messages[key] ?? []
    }

    // MARK: - Auto-refresh
    func startAutoRefresh() {
        stopAutoRefresh()
        Task { await fetchPending() }
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { [weak self] in
                await self?.fetchPending()
            }
        }
    }

    func stopAutoRefresh() {
        timer?.invalidate()
        timer = nil
    }
}