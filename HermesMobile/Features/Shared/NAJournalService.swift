import Foundation

// MARK: - Journal Service
@MainActor
class NAJournalService: ObservableObject {
    static let shared = NAJournalService()

    private let journalURL = URL(string: "https://health.santoslab.de/api/naice/journal")!

    @Published var entries: [NAJournalEntry] = []
    @Published var isLoading = false

    func fetch() async {
        var req = URLRequest(url: journalURL)
        req.timeoutInterval = 10
        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let entries = try? JSONDecoder().decode([NAJournalEntry].self, from: data)
        else { return }
        self.entries = entries
    }

    func addEntry(text: String, mood: String, clarity: Int = 5) async {
        let body: [String: Any] = [
            "text": text,
            "mood": mood,
            "clarity": clarity,
            "source": "ios-app"
        ]
        var req = URLRequest(url: journalURL)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)

        guard let (data, resp) = try? await URLSession.shared.data(for: req),
              let http = resp as? HTTPURLResponse, http.statusCode == 200,
              let result = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entryData = result["entry"] as? [String: Any],
              let id = entryData["id"] as? String,
              let createdAt = entryData["created_at"] as? String
        else { return }

        let entry = NAJournalEntry(
            id: id,
            text: text,
            created_at: createdAt
        )
        self.entries.insert(entry, at: 0)
    }

    var todayCount: Int {
        entries.filter { Calendar.current.isDateInToday(
            ISO8601DateFormatter().date(from: $0.created_at ?? "") ?? Date()
        )}.count
    }
}